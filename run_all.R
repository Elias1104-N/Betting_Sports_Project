#Run_all

cat("\n############################################################\n")
cat("# INICIANDO FLUJO COMPLETO DEL PROYECTO\n")
cat("############################################################\n\n")

tiempo_inicio <- Sys.time()

# NOTA: los scripts de cada fase viven en la subcarpeta R.Scripts/,
# mientras que config.R y este run_all.R están en la raíz del
# proyecto (junto al .Rproj y a la carpeta data/). Ajusta la ruta
# si tu estructura es distinta.
CARPETA_SCRIPTS <- "scripts"

source("config.R")

cat(">>> FASE 0: Renombre de las bases de datos...\n\n")
source(file.path(CARPETA_SCRIPTS, "0.Renombre de las bases de datos.R"))

cat(">>> FASE 1: Descarga (verificación) y limpieza de datos...\n\n")
source(file.path(CARPETA_SCRIPTS, "1. Limpieza de datos.R"))

cat("\n\n>>> FASE 2: Cuotas a probabilidades, margen y remoción...\n\n")
source(file.path(CARPETA_SCRIPTS, "2. Margen y probabilidades.R"))

cat("\n\n>>> FASE 3: Evaluación de la calibración...\n\n")
source(file.path(CARPETA_SCRIPTS, "3. Evaluación de calibración.R"))

cat("\n\n>>> FASE 4: Análisis de desviaciones sistemáticas...\n\n")
source(file.path(CARPETA_SCRIPTS, "4. Desviaciones sistemáticas.R"))

cat("\n\n>>> FASE 5: Comparación entre ligas (Premier League vs. La Liga)...\n\n")
source(file.path(CARPETA_SCRIPTS, "5. comparación ligas.R"))

tiempo_fin <- Sys.time()

cat("\n\n############################################################\n")
cat("# FLUJO COMPLETO TERMINADO\n")
cat(sprintf("# Tiempo total: %.1f minutos\n", as.numeric(difftime(tiempo_fin, tiempo_inicio, units = "mins"))))
cat("############################################################\n")
cat("\nTodos los archivos de salida están en outputs/:\n")
for (f in list.files("outputs", pattern = "\\.csv$")) {
  cat(sprintf("  - %s\n", f))
}