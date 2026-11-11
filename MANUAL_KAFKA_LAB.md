# Manual clic por clic — Práctica Kafka + Prometheus + Grafana en AWS EC2

Práctica calificada con **2 instancias EC2** en AWS Academy Learner Lab:

- **EC2-Kafka:** Apache Kafka 3.7.1 + ZooKeeper + agente JMX Exporter (puerto 7071).
- **EC2-Monitoreo:** Prometheus (9090) y Grafana (3000) en Docker.

Consola de AWS en **inglés**. Orden: **Learner Lab → Security Groups → EC2-Monitoreo → regla 7071 → EC2-Kafka → pruebas → Grafana**.
Tener abierto `user-data-kafka-lab.sh` para copiar (Ctrl+A, Ctrl+C).

| Fase de la práctica | Dónde se cumple |
| :-- | :-- |
| 1. Infraestructura y Security Groups | Secciones 2 a 5 (capturas 1, 2 y 3) |
| 2. Kafka y JMX Exporter | Sección 6 (capturas 4 y 5) |
| 3. Producer y Consumer | Sección 7 (capturas 6 y 7) |
| 4. Prometheus y Grafana en Docker | Sección 8 (capturas 8 y 9) |
| 5. Integración y dashboard | Sección 9 (capturas 10, 11 y 12) |

```
Navegador ──► EC2-Monitoreo :3000 Grafana ──► :9090 Prometheus ──scrape──► EC2-Kafka :7071 JMX Exporter
                                                                               │
                                                  Producer/Consumer ──────────► :9092 Kafka (ZooKeeper :2181)
```

---

## 1. Learner Lab ⏱ min 0

- [ ] **Start Lab** → esperar el círculo verde → clic **AWS**
- [ ] Arriba a la derecha: **United States (N. Virginia)**
- [ ] **Llave SSH (vockey):** en la página del Learner Lab → **AWS Details** → **SSH key → Download PEM**. Se descarga `labsuser.pem`; guardarlo en una carpeta fácil (p. ej. `Descargas`).

---

## 2. Grupo de seguridad de Monitoreo `sg-monitoreo` ⏱ min 1

**EC2 → Security Groups → Create security group**

- [ ] Security group name: `sg-monitoreo`
- [ ] Description: `sg-monitoreo`
- [ ] VPC: la que sale por defecto

**Inbound rules → Add rule** (repetir por cada puerto):

| Type | Port | Source |
| :-- | :-- | :-- |
| SSH | `22` | Anywhere-IPv4 (`0.0.0.0/0`) |
| Custom TCP | `9090` | Anywhere-IPv4 (Prometheus UI) |
| Custom TCP | `3000` | Anywhere-IPv4 (Grafana UI) |

- [ ] **Create security group**

> 📸 **CAPTURA 3 — Grupo de seguridad de Monitoreo (EC2 2):** entrar al `sg-monitoreo` → pestaña **Inbound rules** y capturar las reglas 22, 9090 y 3000.

---

## 3. Lanzar EC2-Monitoreo ⏱ min 5

**EC2 → Instances → Launch instances**

- [ ] Name: `EC2-Monitoreo`
- [ ] AMI: **Ubuntu Server 24.04 LTS**
- [ ] Instance type: **t3.small**
- [ ] Key pair (login): **vockey**
- [ ] **Network settings → Edit:** Auto-assign public IP → **Enable**; Security group → **Select existing** → `sg-monitoreo`
- [ ] **Storage:** 16 GiB gp3
- [ ] **Advanced details → IAM instance profile:** `LabInstanceProfile`
- [ ] **Advanced details → User data:** pegar **todo** el contenido de `user-data-kafka-lab.sh`
- [ ] **Launch instance**

---

## 4. Grupo de seguridad de Kafka `sg-kafka` ⏱ min 7

**EC2 → Security Groups → Create security group**

- [ ] Security group name: `sg-kafka`
- [ ] Description: `sg-kafka`
- [ ] VPC: la misma que `sg-monitoreo`

**Inbound rules → Add rule**

| Type | Port | Source |
| :-- | :-- | :-- |
| SSH | `22` | Anywhere-IPv4 (`0.0.0.0/0`) |
| Custom TCP | `9092` | Anywhere-IPv4 (Kafka broker) |
| Custom TCP | `7071` | **Custom** → IP privada de EC2-Monitoreo con `/32` (ver paso 5) |

- [ ] **Create security group**

---

## 5. Obtener la IP privada de EC2-Monitoreo y abrir el 7071 ⏱ min 9

- [ ] **EC2 → Instances →** clic en `EC2-Monitoreo` → copiar **Private IPv4 address** (p. ej. `172.31.20.15`).
- [ ] **Security Groups →** `sg-kafka` → **Edit inbound rules** → **Add rule**: Custom TCP, port `7071`, Source **Custom** → escribir `IP_PRIVADA_MONITOREO/32` (p. ej. `172.31.20.15/32`) → **Save rules**.

> Alternativa equivalente: como Source poner el propio grupo `sg-monitoreo`. Como la práctica pide la **IP privada**, se usa el `/32`.

> 📸 **CAPTURA 2 — Grupo de seguridad de Kafka (EC2 1):** `sg-kafka` → **Inbound rules** con los puertos 22, 9092 y 7071 (este último con la IP privada de Monitoreo).

---

## 6. Lanzar EC2-Kafka ⏱ min 11

**EC2 → Instances → Launch instances**

- [ ] Name: `EC2-Kafka`
- [ ] AMI: **Ubuntu Server 24.04 LTS**
- [ ] Instance type: **t3.medium** (Kafka necesita al menos 4 GiB de RAM)
- [ ] Key pair (login): **vockey**
- [ ] **Network settings → Edit:** Auto-assign public IP → **Enable**; Security group → **Select existing** → `sg-kafka`
- [ ] **Storage:** 20 GiB gp3
- [ ] **Advanced details → IAM instance profile:** `LabInstanceProfile`
- [ ] **Advanced details → User data:** pegar **todo** el contenido de `user-data-kafka-lab.sh`
- [ ] **Launch instance**

> ⚠️ Es el **mismo** `user-data-kafka-lab.sh` que en Monitoreo. El script detecta el rol por el nombre `EC2-Kafka`.

---

## 7. Capturas 1 y 2 de infraestructura ⏱ min 13

- [ ] **EC2 → Instances:** esperar a que **ambas** estén en **Running** (checks 2/2 pueden tardar ~2 min más).

> 📸 **CAPTURA 1 — Instancias EC2 activas:** la lista con `EC2-Kafka` y `EC2-Monitoreo` en **Running**, mostrando **Public IPv4** y **Private IPv4** de cada una.

---

## 8. Verificar la instalación en EC2-Kafka ⏱ min 16

Los scripts de arranque tardan entre **5 y 10 minutos** (descargan Kafka y Docker). Esperar antes de continuar.

Conectarse por SSH desde la PC (PowerShell, en la carpeta donde está `labsuser.pem`; si pregunta *Are you sure you want to continue connecting*, escribir `yes`):

```bash
ssh -i "labsuser.pem" ubuntu@IP_PUBLICA_EC2_KAFKA
```

Ver el progreso del arranque:

```bash
sudo tail -f /var/log/agro-kafka-lab.log
```

Debe aparecer `KAFKA LISTO: broker 9092, ZooKeeper 2181, JMX Exporter 7071`. Salir con **Ctrl+C**.

---

## 9. Capturas 4 y 5: JMX Exporter y procesos ⏱ min 22

En **EC2-Kafka** (sesión SSH):

**Captura 4:** mostrar el archivo de configuración del agente y la variable que lo activa:

```bash
cat /opt/jmx/jmx_config.yaml
systemctl show kafka -p Environment
```

Debe verse `KAFKA_OPTS=-javaagent:/opt/jmx/jmx_prometheus_javaagent-0.19.0.jar=7071:/opt/jmx/jmx_config.yaml`.

> 📸 **CAPTURA 4 — Configuración del Agente JMX Exporter:** la salida de los dos comandos anteriores en la misma terminal.

**Captura 5:** procesos activos:

```bash
ps aux | grep -E "zookeeper|kafka" | grep -v grep | cut -c1-180
systemctl status zookeeper kafka --no-pager | grep -E "Active|●"
curl -s localhost:7071/metrics | head -5
```

> 📸 **CAPTURA 5 — Procesos de Kafka y ZooKeeper en ejecución:** salida de `ps aux`, el `systemctl status` en `active (running)` y las primeras líneas de `localhost:7071/metrics`.

---

## 10. Captura 6: creación del tópico ⏱ min 26

```bash
kafka-topics.sh --create --topic eventos-negocio --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1
```

Debe responder: **`Created topic eventos-negocio.`**

> 📸 **CAPTURA 6 — Creación del tópico:** el comando y la respuesta `Created topic eventos-negocio.`

---

## 11. Captura 7: productor y consumidor en pantalla dividida ⏱ min 28

En la PC, usar **dos ventanas de SSH** (o `tmux`, o Windows Terminal con dos paneles). Ambas a **EC2-Kafka**.

**Terminal izquierda — Consumidor** (primero, para que quede escuchando):

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic eventos-negocio --from-beginning
```

**Terminal derecha — Productor:**

```bash
kafka-console-producer.sh --bootstrap-server localhost:9092 --topic eventos-negocio
```

Escribir mensajes de prueba en el productor, uno por línea, por ejemplo:

```
{"evento":"nuevo_registro","entidad":"insumo","id":1}
{"evento":"transaccion","monto":150.5}
```

Cada mensaje debe aparecer en la terminal del consumidor **al instante**. Salir de ambos con **Ctrl+C**.

> 📸 **CAPTURA 7 — Flujo de mensajes en tiempo real:** pantalla dividida: productor a la izquierda y consumidor a la derecha, mostrando los mismos mensajes.
>
> Con `tmux` (opcional): `sudo apt install tmux` → `tmux` → `Ctrl+B` y luego `%` divide en dos paneles.

---

## 12. Instalar y verificar Monitoreo ⏱ min 32

Conectarse a **EC2-Monitoreo**:

```bash
ssh -i "labsuser.pem" ubuntu@IP_PUBLICA_EC2_MONITOREO
sudo tail -f /var/log/agro-kafka-lab.log
```

Debe aparecer `MONITOREO LISTO` y `Target: IP_PRIVADA_KAFKA:7071`. Salir con **Ctrl+C**.

---

## 13. Captura 8: prometheus.yml ⏱ min 34

En **EC2-Monitoreo**:

```bash
cat /opt/monitoreo/prometheus.yml
```

La sección `static_configs` debe apuntar a la **IP privada de EC2-Kafka** en el puerto **7071**.

> 📸 **CAPTURA 8 — Archivo prometheus.yml:** la salida del `cat`, con `job_name: kafka_metrics` y `targets` = `IP_PRIVADA_KAFKA:7071`.

---

## 14. Captura 9: contenedores Docker ⏱ min 35

En **EC2-Monitoreo**:

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"
```

Deben estar `prometheus` (9090) y `grafana` (3000) con estado **Up**.

> 📸 **CAPTURA 9 — Contenedores Docker activos:** la salida de `docker ps` con Prometheus y Grafana en **Up**.

---

## 15. Captura 10: targets en Prometheus ⏱ min 37

En el navegador:

```
http://IP_PUBLICA_EC2_MONITOREO:9090/targets
```

El target **`kafka_metrics`** debe estar en **UP** (verde). Si sale **DOWN**, revisar la regla `7071` de `sg-kafka` (paso 5).

> 📸 **CAPTURA 10 — Targets en Prometheus:** la página `/targets` con `kafka_metrics` en **UP**.

---

## 16. Captura 11: Data source en Grafana ⏱ min 39

En el navegador:

```
http://IP_PUBLICA_EC2_MONITOREO:3000
```

- [ ] Usuario: `admin` · Contraseña: `admin` (Grafana pedirá cambiarla: poner una nueva y **anotarla**).
- [ ] **Connections → Data sources → Prometheus** (ya viene aprovisionado).
- [ ] Clic en **Save & test**.

Debe aparecer el mensaje verde **"Data source is working"**.

> 📸 **CAPTURA 11 — Data source Prometheus en Grafana:** la pantalla del data source con el mensaje **"Data source is working"**.

---

## 17. Captura 12: dashboard de Kafka en Grafana ⏱ min 42

Generar tráfico primero (así el dashboard se mueve): en **EC2-Kafka**, volver a ejecutar el productor de la sección 11 y enviar varios mensajes.

En Grafana:

- [ ] **Dashboards → New → New dashboard → Add visualization**
- [ ] Data source: **Prometheus**
- [ ] En **Metric** escribir: `kafka_server_brokertopicmetrics_messagesinpersec_count`
- [ ] Clic en **Run queries**: la gráfica debe subir mientras se envían mensajes.
- [ ] Repetir para otros paneles (opcional), por ejemplo:
  - `kafka_server_brokertopicmetrics_bytesinpersec_count` (bytes de entrada)
  - `kafka_server_brokertopicmetrics_bytesoutpersec_count` (bytes de salida)
  - `kafka_network_requestmetrics_requestspersec_count` (peticiones de red)
- [ ] **Back to dashboard → Save dashboard** (nombre: `Kafka - Operativo`).

> 📸 **CAPTURA 12 — Dashboard operativo de Kafka:** el dashboard con los paneles graficando métricas de Kafka, con la gráfica reaccionando al tráfico de la sección 11.

---

## 18. Apagar para ahorrar créditos ⏱ al final

- [ ] **EC2 → Instances →** seleccionar `EC2-Kafka` y `EC2-Monitoreo` → **Instance state → Stop instance**.
- [ ] Al terminar la práctica, **Stop Lab** en Learner Lab.

---

## Problemas frecuentes

| Síntoma | Causa | Solución |
| :-- | :-- | :-- |
| `kafka_metrics` sale **DOWN** en `/targets` | La regla `7071` de `sg-kafka` no tiene la IP privada de Monitoreo | Paso 5: poner `IP_PRIVADA_MONITOREO/32` |
| `ssh` no conecta | El `.pem` sin permisos o instancia aún arrancando | `chmod 400 llave.pem` (en Linux/WSL) · esperar 2 min |
| `Connection refused` al producir mensajes | Kafka aún no terminó de arrancar | Ver `sudo tail -f /var/log/agro-kafka-lab.log` y esperar `KAFKA LISTO` |
| `ERROR: el nombre ... no corresponde a ningun rol` en el log | La EC2 no se llama `EC2-Kafka` ni `EC2-Monitoreo` | Renombrar la instancia (**Manage tags → Name**) y reiniciarla |
| `SIN PERMISOS AWS` en el log | Falta `LabInstanceProfile` | **Actions → Security → Modify IAM role** → `LabInstanceProfile` |
| Grafana no abre en 3000 | El contenedor aún no subió | `docker ps` y `sudo docker logs grafana` |
| El dashboard no muestra datos | No se generó tráfico o el rango de tiempo es muy corto | Enviar mensajes y poner **Last 15 minutes** |
