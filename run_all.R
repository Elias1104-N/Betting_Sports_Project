# ==============================================================================
# Proyecto 2 - ¿Están bien calibradas las casas de apuestas?
# Script maestro de ejecución reproducible (run_all.R)
# ==============================================================================
# Orquesta el flujo completo, desde los CSV crudos hasta el reporte
# de calibración autogenerado. Los scripts viven en scripts/ y se
# localizan por su NÚMERO de fase (0., 1., ...), de modo que no
# dependen de tildes ni de la codificación del nombre de archivo.
# ==============================================================================

cat("\n############################################################\n")
cat("# INICIANDO FLUJO COMPLETO DEL PROYECTO\n")
cat("############################################################\n\n")

tiempo_inicio <- Sys.time()
tiempos_fase <- list()

# 1. Ubicarse en la raíz del proyecto si se ejecuta desde una subcarpeta

if (!file.exists("config.R")) {
  if (file.exists("../config.R")) {
    setwd("..")
  } else if (file.exists("../../config.R")) {
    setwd("../..")
  } else {
    stop("No se encontró config.R. Ejecuta run_all.R desde la raíz del proyecto.")
  }
  cat("Directorio de trabajo ajustado a la raíz del proyecto:", getwd(), "\n")
}

# ---- Registro de ejecución (logs/) -------------------------------------------

if (!dir.exists("logs")) dir.create("logs", recursive = TRUE)
archivo_log <- file.path("logs", sprintf("run_%s.log", format(Sys.time(), "%Y%m%d_%H%M%S")))
con_log <- file(archivo_log, open = "wt")

sink(con_log, split = TRUE)       # salida normal (cat, print)
sink(con_log, type = "message")   # warnings, mensajes y errores

# [CORREGIDO] on.exit() a nivel de script NO funciona de forma confiable:
# solo se dispara dentro de una función. Por eso todo el flujo se envuelve
# en tryCatch(..., finally = ...) más abajo — finally SÍ se garantiza que
# corra, con o sin error, sin importar el contexto.

cat(sprintf("Registro de ejecución: %s\n", archivo_log))
cat(sprintf("Fecha/hora de inicio: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat(sprintf("Versión de R: %s\n\n", R.version.string))

cat("---- Entorno de ejecución ----\n")
info_sistema <- Sys.info()
cat(sprintf("Sistema operativo: %s %s\n", info_sistema[["sysname"]], info_sistema[["release"]]))
cat(sprintf("Usuario: %s\n", info_sistema[["user"]]))
cat(sprintf("Directorio de trabajo: %s\n\n", getwd()))

cat("---- Paquetes cargados (sessionInfo) ----\n")
print(sessionInfo())
cat("\n")

# [CORREGIDO] Todo el resto del flujo queda dentro de este tryCatch.
tryCatch({
  
  # 2. Configuración central (alcance, parámetros, rutas y paquetes)
  
  source("config.R", encoding = "UTF-8")
  
  CARPETA_SCRIPTS <- "scripts"
  
  # 3. Localiza un script de fase por su número y lo ejecuta
  
  ejecutar_fase <- function(numero, nombre_fase) {
    archivo <- list.files(CARPETA_SCRIPTS, pattern = sprintf("^%d\\..*\\.R$", numero),
                          full.names = TRUE)
    if (length(archivo) == 0) {
      stop(sprintf("\n[ERROR] No se encontró el script de la fase %d en '%s/'.\nDirectorio actual: '%s'\n",
                   numero, CARPETA_SCRIPTS, getwd()), call. = FALSE)
    }
    cat(sprintf("\n>>> %s\n-> Archivo: %s\n\n", toupper(nombre_fase), basename(archivo[1])))
    t0 <- Sys.time()
    source(archivo[1], encoding = "UTF-8")
    duracion <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    tiempos_fase[[nombre_fase]] <<- duracion
    cat(sprintf("\n[Tiempo] %s: %.1f segundos\n", nombre_fase, duracion))
  }
  
  # ---- FASES 0 Y 1: Ingesta y limpieza ---------------------------------------
  # Por defecto el flujo EXIGE los CSV crudos en data/raw/. Solo se permite
  # arrancar desde una base_consolidada.csv ya generada si se activa de forma
  # explícita (USAR_BASE_CONSOLIDADA <- TRUE, por ejemplo en config.R).
  # Así nunca se corre "en silencio" con resultados de una corrida anterior.
  
  if (!exists("USAR_BASE_CONSOLIDADA")) USAR_BASE_CONSOLIDADA <- FALSE
  
  archivos_raw <- list.files(DIR_RAW, pattern = "\\.csv$", full.names = TRUE)
  base_consolidada <- file.path(DIR_OUT, "base_consolidada.csv")
  
  # ---- Trazabilidad de los datos de entrada --------------------------------
  if (length(archivos_raw) > 0) {
    cat("---- Datos de entrada (data/raw/) ----\n")
    checksums <- tools::md5sum(archivos_raw)
    for (i in seq_along(archivos_raw)) {
      n_filas <- nrow(fread(archivos_raw[i], select = 1L))
      cat(sprintf("  %-20s MD5=%s  %d filas\n",
                  basename(archivos_raw[i]), checksums[i], n_filas))
    }
    cat(sprintf("Total: %d archivos, %d filas\n\n",
                length(archivos_raw), sum(sapply(archivos_raw, function(f) nrow(fread(f, select = 1L))))))
  }
  
  if (length(archivos_raw) > 0) {
    ejecutar_fase(0, "Fase 0: Renombre de las bases de datos")
    ejecutar_fase(1, "Fase 1: Verificación de calidad y limpieza de datos")
    
    if (file.exists(base_consolidada)) {
      n_consolidada <- nrow(fread(base_consolidada, select = 1L))
      cat(sprintf("\n[Linaje de datos] Tras Fase 1: %d filas en base_consolidada.csv\n", n_consolidada))
    }
  } else if (USAR_BASE_CONSOLIDADA && file.exists(base_consolidada)) {
    warning("No hay CSV crudos en ", DIR_RAW, ". Se omiten las Fases 0 y 1 y se usa ",
            base_consolidada, " (USAR_BASE_CONSOLIDADA = TRUE). ",
            "Los resultados NO se regeneraron desde los datos originales.",
            call. = FALSE)
  } else {
    stop(sprintf(paste0(
      "\n[ERROR] No hay archivos .csv en '%s'.\n",
      "Coloca ahí los CSV descargados de football-data.co.uk (ver README) y vuelve a correr.\n",
      "Si solo quieres reutilizar una base ya consolidada, define USAR_BASE_CONSOLIDADA <- TRUE ",
      "(requiere '%s')."), DIR_RAW, base_consolidada), call. = FALSE)
  }
  
  # ---- FASES 2 a 5 -----------------------------------------------------------
  
  ejecutar_fase(2, "Fase 2: Conversión a probabilidades y remoción del margen (Multiplicativo, Aditivo, Shin)")
  
  archivo_prob <- file.path(DIR_OUT, "base_con_probabilidades.csv")
  if (file.exists(archivo_prob)) {
    n_prob <- nrow(fread(archivo_prob, select = 1L))
    cat(sprintf("[Linaje de datos] Tras Fase 2: %d filas en base_con_probabilidades.csv\n\n", n_prob))
  }
  
  ejecutar_fase(3, "Fase 3: Evaluación de calibración, Murphy, RPS y contrastes apareados")
  ejecutar_fase(4, "Fase 4: Sesgo favorito-longshot y Apertura vs. Cierre")
  ejecutar_fase(5, sprintf("Fase 5: Comparación entre ligas (%s)",
                           paste(NOMBRES_LIGA[LIGAS], collapse = " vs. ")))
  
  # ---- FASE 6: Reporte de calibración autogenerado (Entregable 3) -----------
  
  cat("\n\n>>> FASE 6: Compilando el reporte de calibración autogenerado...\n\n")
  reporte_rmd <- list.files(CARPETA_SCRIPTS, pattern = "^6\\..*\\.Rmd$", full.names = TRUE)
  if (length(reporte_rmd) == 0) {
    stop("No se encontró el .Rmd de la Fase 6 en '", CARPETA_SCRIPTS, "/'.", call. = FALSE)
  }
  
  if (!rmarkdown::pandoc_available()) {
    stop("Pandoc no está disponible. Ejecuta desde RStudio o instala Pandoc ",
         "(https://pandoc.org/installing.html) y vuelve a correr.", call. = FALSE)
  }
  
  t0_reporte <- Sys.time()
  rmarkdown::render(
    input         = reporte_rmd[1],
    output_dir    = DIR_OUT,
    output_file   = "reporte_calibracion.html",
    knit_root_dir = getwd(),
    envir         = new.env(),
    quiet         = TRUE
  )
  tiempos_fase[["Fase 6: Reporte"]] <- as.numeric(difftime(Sys.time(), t0_reporte, units = "secs"))
  cat(sprintf("¡Reporte HTML autogenerado con éxito en %s/reporte_calibracion.html! (%.1f segundos)\n",
              DIR_OUT, tiempos_fase[["Fase 6: Reporte"]]))
  
  tiempo_fin <- Sys.time()
  
  cat("\n\n############################################################\n")
  cat("# FLUJO COMPLETO TERMINADO EXITOSAMENTE\n")
  cat(sprintf("# Tiempo total: %.2f minutos\n", as.numeric(difftime(tiempo_fin, tiempo_inicio, units = "mins"))))
  cat("############################################################\n")
  
  cat("\n---- Tiempo por fase ----\n")
  for (nombre in names(tiempos_fase)) {
    cat(sprintf("  %-55s %6.1f s\n", nombre, tiempos_fase[[nombre]]))
  }
  cat(sprintf("  %-55s %6.1f s\n", "TOTAL", sum(unlist(tiempos_fase))))
  
  cat(sprintf("\nArchivos generados en %s/:\n", DIR_OUT))
  for (f in list.files(DIR_OUT, pattern = "\\.(csv|html)$")) {
    cat(sprintf("  - %s\n", f))
  }
  
}, error = function(e) {
  # [NUEVO] Si algo falla, queda registrado explícitamente en el log,
  # con el mensaje de error completo, antes de que finally cierre todo.
  cat(sprintf("\n\n[ERROR] El flujo se interrumpió: %s\n", conditionMessage(e)))
}, finally = {
  # [CORREGIDO] Esto reemplaza al on.exit() que no se disparaba.
  # finally SÍ se garantiza que corre, haya error o no.
  sink(type = "message")
  sink()
  close(con_log)
  cat(sprintf("\n[Log cerrado: %s]\n", archivo_log))
})