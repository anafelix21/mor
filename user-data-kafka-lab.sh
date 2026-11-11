#!/bin/bash
# ==============================================================================
# AGROPACAYALES - USER DATA PRACTICA KAFKA + PROMETHEUS + GRAFANA (AWS EC2)
# EL MISMO SCRIPT EN LAS 2 EC2. NO SE EDITA NADA. Cada EC2 decide su rol por el
# nombre (tag "Name"):
#   EC2-Kafka      -> Kafka 3.7.1 + ZooKeeper + JMX Exporter 0.19.0 (puerto 7071)
#   EC2-Monitoreo  -> Docker con Prometheus (9090) y Grafana (3000)
# La IP privada de Kafka la descubre sola el nodo de Monitoreo con la API de AWS.
# Requisito: perfil de IAM "LabInstanceProfile" en las 2 EC2 (Learner Lab).
# Progreso: EC2 > Acciones > Supervisar y solucionar problemas > Obtener registro del sistema
# Log en la EC2: /var/log/agro-kafka-lab.log
# ==============================================================================
exec > >(tee -a /var/log/agro-kafka-lab.log) 2>&1

# ---------- Constantes del laboratorio ----------
KAFKA_VERSION="3.7.1"
KAFKA_URL="https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz"
JMX_URL="https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.19.0/jmx_prometheus_javaagent-0.19.0.jar"
GRAFANA_ADMIN_PASS="admin"   # Cambiarla en el primer ingreso a Grafana

log() { echo "[$(date +%H:%M:%S)] [AGRO-LAB] $*"; }
imds() {
  local t; t=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')
  curl -s -H "X-aws-ec2-metadata-token: $t" "http://169.254.169.254/latest/meta-data/$1"
}

# ---------- Base comun ----------
export DEBIAN_FRONTEND=noninteractive
echo 'DPkg::Lock::Timeout "600";' > /etc/apt/apt.conf.d/99agro-lock
apt-get update -y && apt-get install -y curl jq unzip netcat-openbsd
if ! command -v aws >/dev/null; then
  curl -sSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscli.zip
  unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install
fi
AWS_DEFAULT_REGION="$(imds placement/region)"; export AWS_DEFAULT_REGION
INSTANCE_ID="$(imds instance-id)"
PRIVATE_IP="$(imds local-ipv4)"

until aws sts get-caller-identity >/dev/null 2>&1; do
  log "SIN PERMISOS AWS: asigna LabInstanceProfile (Acciones > Seguridad > Modificar rol de IAM). Reintentando..."
  sleep 20
done

NAME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" Name=key,Values=Name --query 'Tags[0].Value' --output text)
case "$(echo "$NAME" | tr '[:upper:]' '[:lower:]')" in
  *kafka*)     ROLE=kafka ;;
  *monitoreo*) ROLE=monitoreo ;;
  *) log "ERROR: el nombre '$NAME' no corresponde a ningun rol (usa EC2-Kafka o EC2-Monitoreo)"; exit 1 ;;
esac
log "EC2 '$NAME' (IP privada $PRIVATE_IP) -> rol: $ROLE"

# ==============================================================================
# ROL: KAFKA (EC2 1) - Kafka + ZooKeeper + JMX Exporter
# ==============================================================================
if [ "$ROLE" = kafka ]; then
  apt-get install -y openjdk-17-jre-headless
  id kafka >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin kafka

  log "Descargando Kafka ${KAFKA_VERSION}"
  curl -fsSL "$KAFKA_URL" -o /tmp/kafka.tgz
  rm -rf /opt/kafka && mkdir -p /opt/kafka
  tar -xzf /tmp/kafka.tgz -C /opt/kafka --strip-components=1

  log "Descargando JMX Exporter 0.19.0"
  mkdir -p /opt/jmx
  curl -fsSL "$JMX_URL" -o /opt/jmx/jmx_prometheus_javaagent-0.19.0.jar

  # Reglas JMX Exporter: convierten los MBeans de Kafka en metricas Prometheus
  # (p. ej. kafka_server_brokertopicmetrics_messagesinpersec_count)
  cat > /opt/jmx/jmx_config.yaml <<'JMXEOF'
lowercaseOutputName: true
lowercaseOutputLabelNames: true
rules:
  - pattern: "kafka.server<type=(.+), name=(.+)><>Count"
    name: kafka_server_$1_$2_count
    type: COUNTER
  - pattern: "kafka.server<type=(.+), name=(.+)><>Value"
    name: kafka_server_$1_$2
    type: GAUGE
  - pattern: "kafka.network<type=(.+), name=(.+)><>Count"
    name: kafka_network_$1_$2_count
    type: COUNTER
  - pattern: "kafka.network<type=(.+), name=(.+)><>Value"
    name: kafka_network_$1_$2
    type: GAUGE
  - pattern: "kafka.controller<type=(.+), name=(.+)><>Value"
    name: kafka_controller_$1_$2
    type: GAUGE
JMXEOF

  # Configuracion del broker: escucha en todas las interfaces, anuncia la IP privada
  cat > /opt/kafka/config/server.properties <<EOF
broker.id=1
listeners=PLAINTEXT://0.0.0.0:9092
advertised.listeners=PLAINTEXT://${PRIVATE_IP}:9092
log.dirs=/var/lib/kafka-logs
zookeeper.connect=localhost:2181
num.partitions=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
auto.create.topics.enable=true
EOF
  sed -i 's#^dataDir=.*#dataDir=/var/lib/zookeeper#' /opt/kafka/config/zookeeper.properties
  mkdir -p /var/lib/kafka-logs /var/lib/zookeeper
  chown -R kafka:kafka /opt/kafka /opt/jmx /var/lib/kafka-logs /var/lib/zookeeper

  # Servicios systemd: ZooKeeper y Kafka (Kafka lleva el agente JMX en KAFKA_OPTS)
  cat > /etc/systemd/system/zookeeper.service <<'EOF'
[Unit]
Description=Apache ZooKeeper (Lab AgroPacayales)
After=network.target

[Service]
Type=simple
User=kafka
ExecStart=/opt/kafka/bin/zookeeper-server-start.sh /opt/kafka/config/zookeeper.properties
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  cat > /etc/systemd/system/kafka.service <<EOF
[Unit]
Description=Apache Kafka Broker + JMX Exporter (Lab AgroPacayales)
After=zookeeper.service
Requires=zookeeper.service

[Service]
Type=simple
User=kafka
Environment="KAFKA_HEAP_OPTS=-Xms1G -Xmx1G"
Environment="KAFKA_OPTS=-javaagent:/opt/jmx/jmx_prometheus_javaagent-0.19.0.jar=7071:/opt/jmx/jmx_config.yaml"
ExecStartPre=/bin/sleep 20
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now zookeeper kafka

  # Comandos de Kafka disponibles en cualquier sesion SSH (los scripts exigen su ruta real, por eso no se usan enlaces)
  echo 'export PATH=$PATH:/opt/kafka/bin' > /etc/profile.d/kafka.sh

  wait_port() { until nc -z -w 3 "$1" "$2"; do log "Esperando $1:$2 ..."; sleep 10; done; }
  wait_port localhost 2181
  wait_port localhost 9092
  wait_port localhost 7071
  log "KAFKA LISTO: broker 9092, ZooKeeper 2181, JMX Exporter 7071 (IP privada $PRIVATE_IP)"
fi

# ==============================================================================
# ROL: MONITOREO (EC2 2) - Prometheus + Grafana en Docker
# ==============================================================================
if [ "$ROLE" = monitoreo ]; then
  apt-get install -y docker.io
  systemctl enable --now docker

  # Buscar la IP privada de la EC2-Kafka (puede tardar: se espera a que exista)
  KAFKA_IP=""
  until [ -n "$KAFKA_IP" ] && [ "$KAFKA_IP" != "None" ]; do
    KAFKA_IP=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=EC2-Kafka" "Name=instance-state-name,Values=running" \
      --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
    [ -n "$KAFKA_IP" ] && [ "$KAFKA_IP" != "None" ] || { log "Esperando la EC2-Kafka ..."; sleep 15; }
  done
  log "EC2-Kafka encontrada en IP privada $KAFKA_IP"

  mkdir -p /opt/monitoreo/grafana/provisioning/datasources
  # prometheus.yml: el target apunta a la IP privada de Kafka, puerto 7071
  cat > /opt/monitoreo/prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: kafka_metrics
    static_configs:
      - targets: ['${KAFKA_IP}:7071']
EOF

  # Data source de Grafana aprovisionado (apunta al contenedor prometheus)
  cat > /opt/monitoreo/grafana/provisioning/datasources/prometheus.yml <<'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF

  docker network create agro-monitoreo 2>/dev/null || true
  docker rm -f prometheus grafana 2>/dev/null || true
  docker run -d --name prometheus --restart always --network agro-monitoreo -p 9090:9090 \
    -v /opt/monitoreo/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
    prom/prometheus:latest
  docker run -d --name grafana --restart always --network agro-monitoreo -p 3000:3000 \
    -e GF_SECURITY_ADMIN_PASSWORD="$GRAFANA_ADMIN_PASS" \
    -v /opt/monitoreo/grafana/provisioning:/etc/grafana/provisioning:ro \
    grafana/grafana:latest

  wait_port() { until nc -z -w 3 "$1" "$2"; do log "Esperando $1:$2 ..."; sleep 10; done; }
  wait_port localhost 9090
  wait_port localhost 3000
  log "MONITOREO LISTO: Prometheus 9090, Grafana 3000. Target: ${KAFKA_IP}:7071"
fi
