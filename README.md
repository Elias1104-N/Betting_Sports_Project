# ¿Están bien calibradas las casas de apuestas?

## Autores

- Elias Jose Parra Royero
- Maria Monica Murillo Rincon

Análisis metodológico de las probabilidades implícitas en cuotas 1X2 (Victoria Local / Empate / Victoria Visitante). El proyecto no busca una estrategia de apuestas — evalúa, con rigor estadístico, qué tan bien calibradas están las probabilidades que publican distintas casas de apuestas frente a lo que realmente ocurre en los partidos.

**El margen de las casas garantiza, en promedio, un valor esperado negativo para quien apuesta.** Este trabajo no intenta vencer esa ventaja: audita la calidad de un pronóstico ajeno, el mismo ejercicio que se aplica a modelos de riesgo crediticio, pronóstico del clima o mantenimiento predictivo.

## Alcance

| | |
|---|---|
| **Ligas** | Premier League (E0), La Liga (SP1) |
| **Temporadas** | 2012/13 a 2019/20 (8 temporadas) |
| **Operadores principales** | B365, PS (Pinnacle apertura), PSC (Pinnacle cierre), WH |
| **Fuente de datos** | [football-data.co.uk](https://www.football-data.co.uk/data.php) |

Todo el alcance (ligas, temporadas, operadores) se controla desde un único archivo: `config.R`. No hay valores hardcodeados en ningún otro script.

> **Nota sobre Pinnacle:** existe una advertencia pública sobre la confiabilidad de las cuotas de Pinnacle publicadas en football-data.co.uk después de julio de 2025. El alcance de este proyecto (2012–2019) es anterior a esa fecha, por lo que no aplica — se revisó explícitamente y se descarta como limitación.

## Estructura del repositorio

```
.
├── config.R              # Único archivo a tocar para cambiar alcance
├── run_all.R              # Script maestro: ejecuta todo el flujo de punta a punta
├── scripts/
│   ├── 0. Renombre de las bases de datos.R   # Detecta liga/temporada y renombra los CSV descargados
│   ├── 1. Limpieza de datos.R                # Consolidación, validación, inventario de cobertura
│   ├── 2. Margen y probabilidades.R          # Conversión a probabilidades, remoción del margen
│   ├── 3. Evaluación de calibración.R        # Curvas de calibración, Brier, RPS, Murphy, Hosmer-Lemeshow
│   ├── 4. Desviaciones sistemáticas.R        # Sesgo favorito-longshot, apertura vs. cierre
│   ├── 5. comparación ligas.R                # Comparación Premier League vs. La Liga
│   └── 6. Reporte de calibración.Rmd         # Reporte autogenerado (entregable 3)
├── data/
│   ├── raw/               # CSV originales (NO versionados — ver "Preparar los datos")
│   └── processed/         # Reservado, actualmente sin uso activo en el flujo
├── outputs/                # Todas las salidas del análisis (NO versionado, se regenera solo)
├── logs/                   # (NO versionado)
└── renv.lock                # Entorno reproducible de paquetes R
```

## Requisitos previos

- R (≥ 4.1 recomendado) y RStudio.
- El proyecto usa [`renv`](https://rstudio.github.io/renv/) para fijar las versiones exactas de los paquetes. Al abrir `Betting_Sports_Project.Rproj` por primera vez, corre:

```r
renv::restore()
```

Esto instala automáticamente todos los paquetes necesarios (`data.table`, `dplyr`, `binom`, `ggplot2`, `rmarkdown`, `knitr`, entre otros) en las versiones exactas registradas en `renv.lock`.

## Preparar los datos (paso manual, obligatorio antes de correr el flujo)

La descarga de los datos **no está automatizada** — es un paso manual único que debes hacer antes de la primera corrida (o cada vez que amplíes el alcance a una liga/temporada nueva):

1. Ve a [football-data.co.uk/data.php](https://www.football-data.co.uk/data.php) y descarga el CSV de cada combinación liga-temporada dentro del alcance definido en `config.R` (por defecto: E0 y SP1, 2012/13 a 2019/20 → 16 archivos).
2. Coloca todos los CSV descargados, con cualquier nombre, dentro de `data/raw/`.
3. Corre `scripts/0. Renombre de las bases de datos.R`. Este script detecta automáticamente la liga y la temporada leyendo el contenido de cada archivo (columnas `Div` y `Date`, no el nombre del archivo) y los renombra al formato estándar que espera el resto del flujo: `{Liga}_{Temporada}.csv` (ej. `E0_1213.csv`).
4. Al final te dirá si las 16 combinaciones esperadas están completas, o cuáles faltan.

Si corres `run_all.R` sin haber hecho este paso, la Fase 0 va a fallar de inmediato con un error explícito ("No se encontraron archivos .csv en data/raw") — es el comportamiento esperado, no un bug.

## Cómo correr el análisis completo

Con los datos ya en `data/raw/` (paso anterior) y el entorno restaurado (`renv::restore()`):

```r
source("run_all.R")
```

Esto ejecuta, en orden: renombrado de archivos (Fase 0), limpieza y consolidación (Fase 1), tratamiento del margen (Fase 2), evaluación de calibración (Fase 3), desviaciones sistemáticas (Fase 4), comparación entre ligas (Fase 5), y genera el reporte de calibración autogenerado (Fase 6) en `outputs/reporte_calibracion.html`.

Todas las salidas (CSV y el reporte HTML) se escriben en `outputs/`, que se regenera por completo en cada corrida — no es necesario, ni se debe, editar nada ahí a mano.

> **Sobre el reporte (`outputs/reporte_calibracion.html`):** se genera únicamente a través de `run_all.R`. No lo renderices con el botón "Knit" de RStudio directamente sobre el `.Rmd` — al ejecutarse así, el `.Rmd` no resuelve correctamente la ruta a `config.R` y falla. El flujo soportado es siempre `run_all.R` completo.

## Qué hace cada fase

| Fase | Script | Qué produce |
|---|---|---|
| 0 | Renombre | Normaliza nombres de archivo en `data/raw/` |
| 1 | Limpieza | `base_consolidada.csv`, `inventario_cobertura.csv` |
| 2 | Margen | `base_con_probabilidades.csv`, `distribucion_margen.csv`, `sensibilidad_metodos.csv` |
| 3 | Calibración | Curvas de calibración, Brier, RPS, descomposición de Murphy, Hosmer-Lemeshow (con corrección de Holm) |
| 4 | Desviaciones | Sesgo favorito-longshot, comparación apertura vs. cierre (ambos con corrección de Holm donde aplica) |
| 5 | Comparación de ligas | Margen y Brier, Premier League vs. La Liga |
| 6 | Reporte | `outputs/reporte_calibracion.html` — consolida curvas, desviaciones, reglas de puntuación y comparación entre métodos de margen |

## Metodología — decisiones relevantes

- **Margen:** se aplican dos métodos obligatorios (multiplicativo, aditivo) a todos los operadores, más el método de Shin a los 4 operadores principales.
- **Muestra común apareada:** las Fases 3 y 4 restringen el análisis entre operadores a los partidos donde los 4 operadores principales tienen cuotas completas, para que las comparaciones sean válidas.
- **Independencia de observaciones:** el test de Hosmer-Lemeshow se corre por separado para cada resultado (H/D/A), porque las tres filas que aporta un mismo partido no son independientes entre sí.
- **Comparaciones múltiples:** se aplica corrección de Holm en las tres familias de pruebas que lo requieren (Hosmer-Lemeshow, sesgo favorito-longshot, comparación de Brier entre operadores).
- **Dependencia residual:** la dependencia más amplia entre partidos de una misma temporada/jornada (mismo equipo, mismo calendario) no se corrige técnicamente — se declara como limitación en el informe técnico.

## Encuadre

Este proyecto es un ejercicio académico de evaluación de pronósticos probabilísticos. Ningún resultado, gráfico o conclusión debe interpretarse como recomendación de apuesta.