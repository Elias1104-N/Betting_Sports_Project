# ============================================================
# Proyecto 2 - ¿Están bien calibradas las casas de apuestas?
# Configuración central del proyecto
# ============================================================
# Todos los parámetros que definen el ALCANCE del análisis viven
# aquí. Para analizar otra liga, otro rango de temporadas, u otros
# operadores principales, este es el ÚNICO archivo que hay que
# tocar - ningún otro script tiene estos valores hardcodeados.
# ============================================================

# ---- Alcance: ligas y temporadas --------------------------------

LIGAS <- c("E0", "SP1")                 # E0 = Premier League, SP1 = La Liga
NOMBRES_LIGA <- c(E0 = "Premier League", SP1 = "La Liga")

# football-data.co.uk codifica la temporada como "AABB" (ej. "1213"
# = temporada 2012/13). anios_inicio define el rango: 2012 -> temporada
# 2012/13, hasta 2019 -> temporada 2019/20.

anios_inicio <- 2012:2019
TEMPORADAS <- sprintf("%02d%02d", anios_inicio %% 100, (anios_inicio + 1) %% 100)

# ---- Operadores principales para las Fases 3 y 4 -----------------
# Elegidos por tener cobertura casi completa (>99%) en las 16
# combinaciones liga-temporada (ver inventario_cobertura.csv y el
# resumen de la Fase 2 para la justificación completa).

OPERADORES_PRINCIPALES <- c("B365", "PS", "PSC", "WH")

# ---- Parámetros metodológicos -------------------------------------

N_BINS <- 10  # intervalos para la curva de calibración (esquema principal: igual ancho)

# ---- Rutas de carpetas ---------------------------------------------

DIR_RAW <- "data/raw"
DIR_OUT <- "outputs"

dir.create(DIR_RAW, recursive = TRUE, showWarnings = FALSE)
dir.create(DIR_OUT, recursive = TRUE, showWarnings = FALSE)

# ---- Paquetes usados en todo el flujo -------------------------------

paquetes_proyecto <- c("data.table", "dplyr", "purrr", "readr", "stringr",
                        "lubridate", "binom")
faltantes <- paquetes_proyecto[!paquetes_proyecto %in% rownames(installed.packages())]
if (length(faltantes) > 0) install.packages(faltantes)
invisible(lapply(paquetes_proyecto, library, character.only = TRUE))
