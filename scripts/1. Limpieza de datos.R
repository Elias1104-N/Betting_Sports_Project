#1 Limpieza de los datos 

# ---- 0. Parámetros 
LIGAS <- c("E0", "SP1")                 # E0 = Premier League, SP1 = La Liga
NOMBRES_LIGA <- c(E0 = "Premier League", SP1 = "La Liga")

# football-data.co.uk codifica la temporada como "AABB"
# (ej. "1213" = temporada 2012/13). Generamos 2012/13 ... 2019/20.
anios_inicio <- 2012:2019
TEMPORADAS <- sprintf("%02d%02d", anios_inicio %% 100, (anios_inicio + 1) %% 100)

DIR_RAW  <- "data/raw"
DIR_OUT  <- "outputs"

dir.create(DIR_RAW, recursive = TRUE, showWarnings = FALSE)
dir.create(DIR_OUT, recursive = TRUE, showWarnings = FALSE)

# ---- 1. Paquetes ---------------------------------------------
paquetes <- c("data.table", "dplyr", "purrr", "readr", "stringr", "lubridate")
instalar_faltantes <- paquetes[!paquetes %in% rownames(installed.packages())]
if (length(instalar_faltantes) > 0) install.packages(instalar_faltantes)
invisible(lapply(paquetes, library, character.only = TRUE))

# ---- 2. Verificación de archivos descargados manualmente --------
# Este script NO descarga nada. Debes bajar tú mismo cada CSV desde
# football-data.co.uk y guardarlo en data/raw/ con el nombre exacto
# "{liga}_{temporada}.csv" (ej. E0_1213.csv, SP1_1213.csv).
#
# URLs para descargar manualmente (patrón general):
#   https://www.football-data.co.uk/mmz4281/{temporada}/{liga}.csv
# Ejemplo: https://www.football-data.co.uk/mmz4281/1213/E0.csv
#
# Nota: el sitio a veces entrega el archivo ya nombrado "E0.csv" o
# "SP1.csv" sin el sufijo de temporada - hay que renombrarlo al
# guardarlo, o el script no lo va a encontrar.
combinaciones <- expand.grid(liga = LIGAS, temporada = TEMPORADAS,
                             stringsAsFactors = FALSE)
combinaciones$ruta <- file.path(DIR_RAW,
                                sprintf("%s_%s.csv", combinaciones$liga, combinaciones$temporada))
combinaciones$ruta[!file.exists(combinaciones$ruta)] <- NA_character_

descargas_fallidas <- combinaciones %>% filter(is.na(ruta))
if (nrow(descargas_fallidas) > 0) {
  message("Archivos faltantes en data/raw/ (revisar nombres/descarga manual):")
  print(descargas_fallidas[, c("liga", "temporada")])
} else {
  message("Los 16 archivos esperados están presentes en data/raw/.")
}

# ---- 3. Lectura y consolidación --------------------------------
# football-data.co.uk cambia las columnas disponibles entre
# temporadas y casas de apuestas. Leemos cada archivo por
# separado y los unimos con rbindlist(fill = TRUE) para no
# perder columnas que no están en todos los archivos.
leer_archivo <- function(ruta, liga, temporada) {
  if (is.na(ruta)) return(NULL)
  df <- tryCatch(
    fread(ruta, encoding = "Latin-1", showProgress = FALSE),
    error = function(e) {
      warning(sprintf("Error leyendo %s: %s", ruta, e$message))
      NULL
    }
  )
  if (is.null(df) || nrow(df) == 0) return(NULL)
  
  # Columnas mínimas que debe traer cualquier archivo válido
  requeridas <- c("Div", "Date", "HomeTeam", "AwayTeam", "FTHG", "FTAG", "FTR")
  faltantes <- setdiff(requeridas, names(df))
  if (length(faltantes) > 0) {
    warning(sprintf("%s %s: faltan columnas %s, se descarta",
                    liga, temporada, paste(faltantes, collapse = ", ")))
    return(NULL)
  }
  
  df[, `:=`(Liga = liga, Temporada = temporada)]
  df
}

lista_datos <- purrr::pmap(
  list(combinaciones$ruta, combinaciones$liga, combinaciones$temporada),
  leer_archivo
)

base <- rbindlist(lista_datos, fill = TRUE)
message(sprintf("Base consolidada: %d partidos, %d columnas",
                nrow(base), ncol(base)))

# ---- 4. Parseo de fechas (dd/mm/aaaa) --------------------------
# football-data.co.uk usa dos formatos de fecha según la época:
# dd/mm/yy (temporadas antiguas) y dd/mm/yyyy (recientes).
# parse_date_time prueba ambos en orden.
base[, Date_parsed := lubridate::parse_date_time(
  Date, orders = c("dmy"), quiet = TRUE
)]
base[, Date_parsed := as.Date(Date_parsed)]

sin_fecha <- sum(is.na(base$Date_parsed))
if (sin_fecha > 0) {
  message(sprintf("Atención: %d filas sin fecha interpretable, revisar", sin_fecha))
}

# ---- 5. Validaciones de calidad --------------------------------

# 5.1 Resultado (FTR) consistente con el marcador
base[, FTR_calculado := fifelse(FTHG > FTAG, "H",
                                fifelse(FTHG < FTAG, "A", "D"))]
inconsistencias_resultado <- base[FTR != FTR_calculado]
message(sprintf("Resultados inconsistentes (FTR vs marcador): %d",
                nrow(inconsistencias_resultado)))

# 5.2 Cuotas imposibles (<= 1) en cualquier columna de cuota
# Las columnas de cuotas siguen el patrón: PREFIJO + H/D/A
# (ej. B365H, B365D, B365A, AvgH, MaxH, etc.)
cols_cuotas <- grep("(H|D|A)$", names(base), value = TRUE)
cols_cuotas <- cols_cuotas[sapply(base[, ..cols_cuotas], is.numeric)]
# Evitar falsos positivos como FTHG/FTAG/HTHG que no son cuotas
cols_cuotas <- setdiff(cols_cuotas, c("FTHG", "FTAG", "HTHG", "HTAG"))

cuotas_imposibles <- base[, lapply(.SD, function(x) sum(x <= 1, na.rm = TRUE)),
                          .SDcols = cols_cuotas]
cuotas_imposibles_total <- sum(unlist(cuotas_imposibles))
message(sprintf("Valores de cuota <= 1 detectados: %d (revisar antes de continuar)",
                cuotas_imposibles_total))
if (cuotas_imposibles_total > 0) {
  print(cuotas_imposibles[, colSums(cuotas_imposibles) > 0, with = FALSE])
}

# 5.3 Duplicados exactos (mismo partido cargado dos veces)
duplicados <- base[duplicated(base[, .(Liga, Temporada, Date_parsed, HomeTeam, AwayTeam)])]
message(sprintf("Filas duplicadas (mismo partido repetido): %d", nrow(duplicados)))

# 5.4 Filtrar la base a partidos válidos
base_valida <- base[
  !is.na(Date_parsed) &
    FTR == FTR_calculado &
    !duplicated(base[, .(Liga, Temporada, Date_parsed, HomeTeam, AwayTeam)])
]

message(sprintf("Base final tras validación: %d partidos (de %d originales)",
                nrow(base_valida), nrow(base)))

# 5.5 Detalle de las filas descartadas (para documentar en el informe)
filas_descartadas <- base[
  is.na(Date_parsed) |
    FTR != FTR_calculado |
    duplicated(base[, .(Liga, Temporada, Date_parsed, HomeTeam, AwayTeam)])
]

if (nrow(filas_descartadas) > 0) {
  cat("\n---- Detalle de filas descartadas (para la sección de limitaciones) ----\n")
  filas_descartadas[, Motivo := fcase(
    is.na(Date_parsed), "Fecha no interpretable",
    FTR != FTR_calculado, "Resultado (FTR) inconsistente con el marcador",
    default = "Duplicado de otro partido ya presente"
  )]
  print(filas_descartadas[, .(Liga, Temporada, Date, HomeTeam, AwayTeam,
                              FTHG, FTAG, FTR, FTR_calculado, Motivo)])
} else {
  message("No hubo filas descartadas.")
}

# ---- 6. Inventario de cobertura --------------------------------
# Identificar qué casas de apuestas tienen columna de cuota H/D/A
# completa (las 3) en cada liga/temporada, y cuántos partidos
# tienen dato no faltante para cada una.
prefijos_casas <- unique(sub("(H|D|A)$", "", cols_cuotas))
# quitar prefijos que no correspondan a una casa real de 3 columnas
prefijos_casas <- prefijos_casas[
  sapply(prefijos_casas, function(p) all(paste0(p, c("H","D","A")) %in% names(base_valida)))
]

inventario <- purrr::map_dfr(prefijos_casas, function(p) {
  cols <- paste0(p, c("H","D","A"))
  base_valida[, .(
    Operador = p,
    Partidos_con_cuota = sum(complete.cases(.SD)),
    Partidos_totales = .N
  ), by = .(Liga, Temporada), .SDcols = cols]
})

inventario[, Cobertura_pct := round(100 * Partidos_con_cuota / Partidos_totales, 1)]
setorder(inventario, Liga, Temporada, -Cobertura_pct)

# 6.1 Vista resumida: cobertura promedio por operador (across todas
# las liga-temporada), para identificar rápido cuáles casas tienen
# datos completos en todo el rango y cuáles solo en parte.
resumen_operadores <- inventario[, .(
  Cobertura_media_pct = round(mean(Cobertura_pct), 1),
  Cobertura_min_pct   = min(Cobertura_pct),
  Liga_temporadas_con_dato = sum(Partidos_con_cuota > 0)
), by = Operador]
setorder(resumen_operadores, -Cobertura_media_pct)

cat("\n---- Resumen de cobertura por operador (promedio en las 16 liga-temporada) ----\n")
print(resumen_operadores)
cat(sprintf("\nOperadores con cobertura completa (100%%) en TODAS las liga-temporada: %d\n",
            sum(resumen_operadores$Cobertura_media_pct == 100 & resumen_operadores$Cobertura_min_pct == 100)))
cat("(Estos son los operadores más confiables para comparar entre sí en la Fase 4.)\n")

# ---- 7. Guardar salidas -----------------------------------------
fwrite(base_valida, file.path(DIR_OUT, "base_consolidada.csv"))
fwrite(inventario, file.path(DIR_OUT, "inventario_cobertura.csv"))

message("Listo. Archivos guardados en data/processed/:")
message(" - base_consolidada.csv")
message(" - inventario_cobertura.csv")

# ---- 8. Resumen final (para copiar y revisar de un vistazo) -----
mostrar_resumen_fase1 <- function() {
  cat("\n")
  cat("================ RESUMEN FASE 1 ================\n")
  cat(sprintf("Archivos esperados:              16 (2 ligas x 8 temporadas)\n"))
  cat(sprintf("Archivos faltantes en data/raw/: %d\n", nrow(descargas_fallidas)))
  if (nrow(descargas_fallidas) > 0) {
    cat("  -> Faltan:\n")
    for (i in seq_len(nrow(descargas_fallidas))) {
      cat(sprintf("     %s %s\n", descargas_fallidas$liga[i], descargas_fallidas$temporada[i]))
    }
  }
  cat(sprintf("Partidos leídos (antes de validar): %d\n", nrow(base)))
  cat(sprintf("Filas sin fecha interpretable:       %d\n", sin_fecha))
  cat(sprintf("Resultados inconsistentes (FTR):     %d\n", nrow(inconsistencias_resultado)))
  cat(sprintf("Valores de cuota <= 1 detectados:    %d\n", cuotas_imposibles_total))
  cat(sprintf("Filas duplicadas:                    %d\n", nrow(duplicados)))
  cat(sprintf("Partidos en base final validada:     %d\n", nrow(base_valida)))
  cat(sprintf("Filas descartadas por validación:    %d (detalle arriba, sección 5.5)\n", nrow(filas_descartadas)))
  cat(sprintf("Operadores detectados en inventario: %d\n", length(unique(inventario$Operador))))
  esperado <- length(LIGAS) * length(TEMPORADAS) * 380
  cat(sprintf("Partidos esperados (%d ligas x %d temporadas x 380): %d\n",
              length(LIGAS), length(TEMPORADAS), esperado))
  cat("--------------------------------------------------\n")
  n_ok <- nrow(base_valida) == esperado
  descargas_ok <- nrow(descargas_fallidas) == 0
  if (descargas_ok && n_ok) {
    cat("ESTADO: Base completa y limpia (las filas descartadas, si las hubo, ya\n")
    cat("        quedaron excluidas correctamente). Lista para la Fase 2.\n")
  } else if (!descargas_ok) {
    cat("ESTADO: Faltan archivos por descargar/renombrar (ver lista arriba).\n")
  } else {
    cat("ESTADO: El conteo final no coincide con lo esperado. Revisar detalle arriba.\n")
  }
  cat("====================================================\n")
}

mostrar_resumen_fase1()
