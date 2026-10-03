# ============================================================
# Proyecto 2 - ¿Están bien calibradas las casas de apuestas?
# Extensión: Comparación entre ligas (Premier League vs. La Liga)
# ============================================================
# Contrasta el "valor de mercado" (margen y calibración) entre las
# dos ligas que ya están dentro del alcance del proyecto (E0 y SP1,
# definidas en config.R). NO amplía el alcance ni descarga datos
# nuevos: solo desagrega por Liga los resultados que las Fases 2-3
# ya calcularon de forma agrupada.
#
# Requiere haber corrido antes las Fases 1-2 (necesita
# base_con_probabilidades.csv y distribucion_margen.csv en
# outputs/).
#
# Preguntas que responde:
#   A) ¿El margen (overround) es distinto entre Premier League y
#      La Liga?
#   B) ¿La calibración (Brier score) es distinta entre las dos ligas?
#      -> Como los partidos de una liga y otra son eventos
#      DISTINTOS (no la misma casa fijando dos precios sobre el
#      mismo partido, como en apertura/cierre), aquí SÍ son muestras
#      independientes, y se usa Wilcoxon/Mann-Whitney para dos
#      muestras independientes (no la versión apareada usada en la
#      Fase 4).
# ============================================================

source("config.R")

base <- fread(file.path(DIR_OUT, "base_con_probabilidades.csv"), encoding = "UTF-8")
distribucion_margen <- fread(file.path(DIR_OUT, "distribucion_margen.csv"), encoding = "UTF-8")

# ---- A. Margen por liga -----------------------------------------------
margen_por_liga <- distribucion_margen[
  Operador %in% OPERADORES_PRINCIPALES,
  .(Margen_medio_pct = round(mean(Margen_medio_pct, na.rm = TRUE), 2),
    N_partidos = sum(N_partidos)),
  by = .(Liga, Operador)
]
setorder(margen_por_liga, Liga, Operador)

message("---- Margen medio por liga y operador ----")
print(margen_por_liga)

margen_resumen_liga <- margen_por_liga[, .(
  Margen_medio_pct = round(mean(Margen_medio_pct), 2)
), by = Liga]
margen_resumen_liga[, Liga_nombre := NOMBRES_LIGA[Liga]]

message("\n---- Margen medio general por liga (promedio de los operadores principales) ----")
print(margen_resumen_liga[, .(Liga_nombre, Margen_medio_pct)])

# ---- B. Reconstruir formato largo (igual que en Fases 3-4) ------------
construir_formato_largo <- function(dt, operador) {
  colH <- paste0("pnorm_mult_", operador, "_H")
  colD <- paste0("pnorm_mult_", operador, "_D")
  colA <- paste0("pnorm_mult_", operador, "_A")
  
  faltan <- setdiff(c(colH, colD, colA), names(dt))
  if (length(faltan) > 0) {
    warning(sprintf("Operador %s: faltan columnas %s, se omite.",
                    operador, paste(faltan, collapse = ", ")))
    return(NULL)
  }
  
  rbindlist(list(
    dt[!is.na(get(colH)), .(Liga, Temporada, Resultado_evaluado = "H",
                            Prob_predicha = get(colH), Ocurrio = as.integer(FTR == "H"))],
    dt[!is.na(get(colD)), .(Liga, Temporada, Resultado_evaluado = "D",
                            Prob_predicha = get(colD), Ocurrio = as.integer(FTR == "D"))],
    dt[!is.na(get(colA)), .(Liga, Temporada, Resultado_evaluado = "A",
                            Prob_predicha = get(colA), Ocurrio = as.integer(FTR == "A"))]
  ))[, Operador := operador]
}

datos_largos <- rbindlist(lapply(OPERADORES_PRINCIPALES, construir_formato_largo, dt = base))

# ---- C. Brier score por liga y operador --------------------------------
calcular_brier_por_liga <- function(dt, operador, liga) {
  colH <- paste0("pnorm_mult_", operador, "_H")
  colD <- paste0("pnorm_mult_", operador, "_D")
  colA <- paste0("pnorm_mult_", operador, "_A")
  
  sub <- dt[Liga == liga & !is.na(get(colH)) & !is.na(get(colD)) & !is.na(get(colA))]
  oH <- as.integer(sub$FTR == "H"); oD <- as.integer(sub$FTR == "D"); oA <- as.integer(sub$FTR == "A")
  brier <- (sub[[colH]] - oH)^2 + (sub[[colD]] - oD)^2 + (sub[[colA]] - oA)^2
  
  fH <- mean(oH); fD <- mean(oD); fA <- mean(oA)
  brier_base_frec <- (fH - oH)^2 + (fD - oD)^2 + (fA - oA)^2
  
  data.table(
    Liga = liga, Operador = operador, N = nrow(sub),
    Brier_operador = round(mean(brier), 4),
    Brier_base_frecuencia = round(mean(brier_base_frec), 4),
    Mejora_vs_frecuencia_pct = round(100 * (mean(brier_base_frec) - mean(brier)) / mean(brier_base_frec), 2)
  )
}

combinaciones <- CJ(Operador = OPERADORES_PRINCIPALES, Liga = LIGAS)
brier_por_liga <- rbindlist(mapply(
  calcular_brier_por_liga,
  operador = combinaciones$Operador, liga = combinaciones$Liga,
  MoreArgs = list(dt = base), SIMPLIFY = FALSE
))
setorder(brier_por_liga, Operador, Liga)

message("\n---- Brier score por liga y operador ----")
print(brier_por_liga)

# ---- D. Contraste formal: Wilcoxon para MUESTRAS INDEPENDIENTES -------
comparar_ligas_wilcoxon <- function(dt, operador) {
  colH <- paste0("pnorm_mult_", operador, "_H")
  colD <- paste0("pnorm_mult_", operador, "_D")
  colA <- paste0("pnorm_mult_", operador, "_A")
  
  sub <- dt[!is.na(get(colH)) & !is.na(get(colD)) & !is.na(get(colA))]
  oH <- as.integer(sub$FTR == "H"); oD <- as.integer(sub$FTR == "D"); oA <- as.integer(sub$FTR == "A")
  brier_partido <- (sub[[colH]] - oH)^2 + (sub[[colD]] - oD)^2 + (sub[[colA]] - oA)^2
  
  test <- wilcox.test(brier_partido ~ sub$Liga)
  
  data.table(
    Operador = operador,
    Brier_medio_E0  = round(mean(brier_partido[sub$Liga == "E0"]), 4),
    Brier_medio_SP1 = round(mean(brier_partido[sub$Liga == "SP1"]), 4),
    Valor_p = signif(test$p.value, 4)
  )
}

contraste_ligas <- rbindlist(lapply(OPERADORES_PRINCIPALES, comparar_ligas_wilcoxon, dt = base))

message("\n---- Contraste Premier League (E0) vs. La Liga (SP1) ----")
message("Prueba: Wilcoxon/Mann-Whitney para MUESTRAS INDEPENDIENTES")
message("(correcta aquí porque los partidos de una liga y otra son eventos distintos,")
message("a diferencia de la comparación apertura/cierre de la Fase 4, que sí es apareada).")
print(contraste_ligas)

# ---- Guardar salidas ----------------------------------------------------
fwrite(margen_por_liga, file.path(DIR_OUT, "margen_por_liga.csv"))
fwrite(brier_por_liga, file.path(DIR_OUT, "brier_por_liga.csv"))
fwrite(contraste_ligas, file.path(DIR_OUT, "contraste_ligas.csv"))

message("\nListo. Archivos guardados en outputs/:")
message(" - margen_por_liga.csv")
message(" - brier_por_liga.csv")
message(" - contraste_ligas.csv")

# ---- Resumen final --------------------------------------------------
cat("\n")
cat("================ RESUMEN: PREMIER LEAGUE vs. LA LIGA ================\n")
cat("A) Margen medio por liga (promedio de los operadores principales):\n")
print(margen_resumen_liga[, .(Liga_nombre, Margen_medio_pct)])
diff_margen <- diff(range(margen_resumen_liga$Margen_medio_pct))
cat(sprintf("-> Diferencia de margen entre ligas: %.2f p.p.\n", diff_margen))
cat("--------------------------------------------------------------------\n")
cat("B) Calibración (Brier score) por liga y operador:\n")
print(brier_por_liga[, .(Liga, Operador, N, Brier_operador)])
cat("--------------------------------------------------------------------\n")
cat("C) Contraste formal (Wilcoxon, muestras independientes):\n")
print(contraste_ligas)
sig <- contraste_ligas[Valor_p < 0.05]
if (nrow(sig) > 0) {
  cat(sprintf("-> Diferencia de calibración estadísticamente significativa (p<0.05) entre\n   ligas en: %s\n",
              paste(sig$Operador, collapse = ", ")))
} else {
  cat("-> No se encontró diferencia estadísticamente significativa en calibración entre las dos ligas.\n")
}
cat("=======================================================================\n")