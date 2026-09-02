# Costes en Railway

Railway factura por **uso real** (RAM-hora, vCPU-hora, GB de volumen, egreso) con resolución por minuto. El plan Hobby incluye ~5 USD/mes de crédito.

## Plan gratuito (Free)

El plan gratuito tiene particularidades que esta plantilla ya contempla:

- **Sleep obligatorio**: los servicios sin cron deben tener *Sleep Application* activado; el servicio Drupal de esta plantilla lo lleva activado. Tras minutos sin tráfico el contenedor se duerme y **no consume RAM/vCPU**; la primera petición despierta el sitio en unos segundos.
- **Ventanas pico**: los despliegues en la región por defecto (Ámsterdam) están bloqueados de 8:00 a 20:00 (hora de Ámsterdam). Despliega fuera de ese horario o cambia la región del servicio/workspace.
- **Un volumen por servicio** y rutas de montaje inmutables: si cambias la ruta del docroot, recrea el servicio para que el volumen nazca en la ruta correcta.

## Presupuesto con los valores por defecto

Supuestos: sitio pequeño-mediano, tráfico moderado (~10–30 GB/mes de egreso incluido en cuotas actuales de Railway según plan).

| Concepto | Configuración por defecto | Estimación mensual |
|---|---|---|
| Servicio Drupal (RAM) | ~250–400 MB reales de uso | 2 – 3 USD |
| Servicio Drupal (vCPU) | uso bajo, picos en instalación/caché | 0,5 – 1 USD |
| Postgres (RAM + vCPU) | ~50–100 MB reales | 0,7 – 1,5 USD |
| Volumen Drupal (`sites/default`) | 1 GB mínimo | ~0,25 USD |
| Volumen Postgres | 1 GB mínimo | ~0,25 USD |
| Red privada | gratuita | 0 |
| **Total estimado** | | **≈ 4 – 6,5 USD/mes** |

> Las tarifas exactas pueden cambiar — verifica en [railway.com/pricing](https://railway.com/pricing). La instalación inicial consume un pico breve de CPU/RAM (Drush installer) que apenas afecta a la media mensual.

## Encaje en el plan Hobby (~5 USD crédito)

Está justo pero dentro. Trucos para dejarlo holgado:

1. **Volumen mínimo**: 1 GB en ambos servicios (no amplíes hasta necesidad real; ampliar es trivial más adelante).
2. **Sleep del servicio Drupal**: Settings → *Sleep Application* duerme el servicio tras X minutos sin tráfico HTTP. Al despertar tarda unos segundos. Con poco tráfico puede ahorrar la mitad del gasto de cómputo. Los volúmenes siguen facturando su precio fijo (pequeño).
3. **No repliques**: `numReplicas: 1` ya viene así.
4. Vigila el consumo en **Usage** del proyecto; ajusta memoria máxima del servicio Drupal (Settings → Resources) si quieres techo duro.

## Cuándo crecer

| Señal | Acción |
|---|---|
| RAM > 80 % sostenido | Sube el límite del servicio Drupal (512 MB → 1 GB) |
| Medios pesados (vídeo, descargas) | Amplía volumen de `sites/default` |
| Tráfico alto / caché externa | Añade Redis + módulo contrib `redis` (fuera del alcance de esta plantilla para mantenerla mínima) |
| Backups | Ver TROUBLESHOOTING → copias de seguridad |
