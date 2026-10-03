# ============================================================
# Proyecto 2 - ¿Están bien calibradas las casas de apuestas?
# Fase 4: Análisis de desviaciones sistemáticas
# ============================================================
# Parte de base_con_probabilidades.csv (Fase 2) y reutiliza la
# lógica de formato largo de la Fase 3. Investiga:
#   A) Sesgo favorito-longshot: ¿se sobrestima la probabilidad de
#      resultados improbables (longshots) y se subestima la de
#      los favoritos?
#   B) Apertura vs. cierre: ¿está mejor calibrado el mercado en el
#      cierre (PSC) que en la apertura (PS)? (bonificable)
#
# IMPORTANTE (trampa metodológica #2 del enunciado): las casas de
# apuestas fijan precios sobre LOS MISMOS PARTIDOS. Los datos son
# APAREADOS, no independientes. Por eso la comparación PS vs. PSC
# se hace con una prueba para datos apareados (Wilcoxon de rangos
# con signo), NO con una prueba de muestras independientes.
# ============================================================

source("config.R")

base <- fread(file.path(DIR_OUT, "base_con_probabilidades.csv"), encoding = "UTF-8")

# [FIX] Consistencia de muestra con la Fase 3: ahí se filtró a los partidos
# donde los 4 operadores principales tienen datos completos ("muestra común
# apareada"), para que las comparaciones entre operadores fueran válidas.
# Esta fase reutiliza ese mismo criterio para que el N por operador en
# favlong/apertura-cierre coincida con el de Brier/HL de la Fase 3 — si no,
# la comparación entre tablas de distintas fases usa partidos ligeramente
# distintos por operador, lo cual genera N inconsistentes sin explicación.

cond_comun <- rep(TRUE, nrow(base))
for (op in OPERADORES_PRINCIPALES) {
  colH <- paste0("pnorm_mult_", op, "_H")
  colD <- paste0("pnorm_mult_", op, "_D")
  colA <- paste0("pnorm_mult_", op, "_A")
  if (all(c(colH, colD, colA) %in% names(base))) {
    cond_comun <- cond_comun & (!is.na(base[[colH]]) & !is.na(base[[colD]]) & !is.na(base[[colA]]))
  }
}
base <- base[cond_comun]
message(sprintf("Muestra común apareada (consistente con Fase 3): %d partidos", nrow(base)))

# ---- 0. Reconstruir formato largo (igual que en la Fase 3) --------
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
  
  largo <- rbindlist(list(
    dt[!is.na(get(colH)), .(Liga, Temporada, Resultado_evaluado = "H",
                            Prob_predicha = get(colH), Ocurrio = as.integer(FTR == "H"))],
    dt[!is.na(get(colD)), .(Liga, Temporada, Resultado_evaluado = "D",
                            Prob_predicha = get(colD), Ocurrio = as.integer(FTR == "D"))],
    dt[!is.na(get(colA)), .(Liga, Temporada, Resultado_evaluado = "A",
                            Prob_predicha = get(colA), Ocurrio = as.integer(FTR == "A"))]
  ))
  largo[, Operador := operador]
  largo
}

datos_largos <- rbindlist(lapply(OPERADORES_PRINCIPALES, construir_formato_largo, dt = base))

# ============================================================
# PARTE A: Sesgo favorito-longshot
# ============================================================
# Idea: agrupar las predicciones por nivel de probabilidad (bins
# finos, ej. 20 grupos) y ver si la desviación (observado - predicho)
# tiene un patrón sistemático: favoritos (prob. alta) con desviación
# positiva (se subestiman) y longshots (prob. baja) con desviación
# negativa (se sobrestiman) es la firma clásica del sesgo.

analizar_favorito_longshot <- function(dt_largo, operador, n_bins = 20) {
  d <- dt_largo[Operador == operador]
  d[, bin := cut(Prob_predicha, breaks = seq(0, 1, length.out = n_bins + 1),
                 include.lowest = TRUE, labels = FALSE)]
  
  resumen <- d[, {
    n <- .N
    aciertos <- sum(Ocurrio)
    ic <- binom.confint(aciertos, n, methods = "wilson")
    .(
      Prob_predicha_media = mean(Prob_predicha),
      Frecuencia_observada = aciertos / n,
      IC_inferior = ic$lower,
      IC_superior = ic$upper,
      N = n
    )
  }, by = bin]
  
  resumen[, Desviacion_pp := 100 * (Frecuencia_observada - Prob_predicha_media)]
  resumen[, Operador := operador]
  setorder(resumen, bin)
  resumen
}

favlong <- rbindlist(lapply(OPERADORES_PRINCIPALES, analizar_favorito_longshot, dt_largo = datos_largos))

# Contraste formal: correlación entre la probabilidad predicha (nivel
# de favoritismo) y la desviación. Una correlación positiva y
# significativa es evidencia de sesgo favorito-longshot (los favoritos
# se subestiman relativamente menos que los longshots, o viceversa
# según el signo).

contraste_favlong <- rbindlist(lapply(OPERADORES_PRINCIPALES, function(op) {
  sub <- favlong[Operador == op]
  test <- cor.test(sub$Prob_predicha_media, sub$Desviacion_pp, method = "spearman")
  data.table(
    Operador = op,
    Correlacion_spearman = round(unname(test$estimate), 3),
    Valor_p = signif(test$p.value, 4),
    # Comparación directa: desviación media en el 20% de probabilidades
    # más bajas (longshots) vs. el 20% más altas (favoritos)
    Desv_longshots_pp = round(mean(sub$Desviacion_pp[sub$bin <= 4]), 2),
    Desv_favoritos_pp = round(mean(sub$Desviacion_pp[sub$bin >= 17]), 2)
  )
}))

# [FIX] Corrección por comparaciones múltiples: 4 pruebas (una por
# operador) evaluadas en conjunto.

contraste_favlong[, Valor_p_ajustado_Holm := p.adjust(Valor_p, method = "holm")]
contraste_favlong[, Significativo_Holm_0.05 := Valor_p_ajustado_Holm < 0.05]

message("---- Sesgo favorito-longshot: correlación entre prob. predicha y desviación ----")
print(contraste_favlong)
message("\nInterpretación:")
message("- Desv_longshots_pp negativo = las probabilidades bajas (longshots) se")
message("  SOBRESTIMAN (ocurren menos de lo que dice el precio) -> sesgo clásico.")
message("- Desv_favoritos_pp positivo = los favoritos se SUBESTIMAN (ganan más de")
message("  lo que dice el precio).")
message("- Correlación positiva y p < 0.05 = evidencia formal de sesgo favorito-longshot.")

# ============================================================
# PARTE B: Apertura (PS) vs. Cierre (PSC) - bonificable
# ============================================================
# Comparación APAREADA: cada partido tiene una cuota de apertura y
# una de cierre de la MISMA casa (Pinnacle), así que no son muestras
# independientes. Se usa el error absoluto de calibración por partido
# (|p_predicha - o| para el resultado observado) y se compara con
# una prueba de Wilcoxon de rangos con signo (no paramétrica, para
# datos apareados, sin asumir normalidad).

datos_ps  <- base[!is.na(pnorm_mult_PS_H) & !is.na(pnorm_mult_PSC_H)]

# Error de Brier por partido (no por resultado) para cada uno de los
# dos momentos (apertura y cierre), sobre el mismo conjunto de partidos.
oH <- as.integer(datos_ps$FTR == "H")
oD <- as.integer(datos_ps$FTR == "D")
oA <- as.integer(datos_ps$FTR == "A")

brier_apertura <- (datos_ps$pnorm_mult_PS_H  - oH)^2 + (datos_ps$pnorm_mult_PS_D  - oD)^2 + (datos_ps$pnorm_mult_PS_A  - oA)^2
brier_cierre   <- (datos_ps$pnorm_mult_PSC_H - oH)^2 + (datos_ps$pnorm_mult_PSC_D - oD)^2 + (datos_ps$pnorm_mult_PSC_A - oA)^2

test_apareado <- wilcox.test(brier_cierre, brier_apertura, paired = TRUE)

resumen_apertura_cierre <- data.table(
  N_partidos = length(brier_apertura),
  Brier_medio_apertura_PS = round(mean(brier_apertura), 4),
  Brier_medio_cierre_PSC = round(mean(brier_cierre), 4),
  Diferencia = round(mean(brier_cierre) - mean(brier_apertura), 4),
  Mejora_cierre_pct = round(100 * (mean(brier_apertura) - mean(brier_cierre)) / mean(brier_apertura), 2),
  Wilcoxon_V = unname(test_apareado$statistic),
  Valor_p = signif(test_apareado$p.value, 4)
)

message("\n---- Apertura (PS) vs. Cierre (PSC): comparación apareada (Wilcoxon) ----")
print(resumen_apertura_cierre)
message("\nInterpretación: Brier menor en cierre + Mejora_cierre_pct positivo =")
message("las cuotas de cierre están mejor calibradas (incorporan más información).")
message("El valor_p viene de una prueba APAREADA (Wilcoxon), correcta porque")
message("apertura y cierre son la MISMA casa sobre los MISMOS partidos.")

# ---- Guardar salidas ------------------------------------------------
fwrite(favlong, file.path(DIR_OUT, "sesgo_favorito_longshot_detalle.csv"))
fwrite(contraste_favlong, file.path(DIR_OUT, "sesgo_favorito_longshot_contraste.csv"))
fwrite(resumen_apertura_cierre, file.path(DIR_OUT, "apertura_vs_cierre.csv"))

message("\nListo. Archivos guardados en outputs/:")
message(" - sesgo_favorito_longshot_detalle.csv")
message(" - sesgo_favorito_longshot_contraste.csv")
message(" - apertura_vs_cierre.csv")

# ---- Resumen final ----------------------------------------------------
cat("\n")
cat("================ RESUMEN FASE 4 ================\n")
cat("A) Sesgo favorito-longshot:\n")
print(contraste_favlong)
sesgo_detectado <- contraste_favlong[Significativo_Holm_0.05 == TRUE & Correlacion_spearman > 0]
if (nrow(sesgo_detectado) > 0) {
  cat(sprintf("-> Sesgo favorito-longshot detectado (p<0.05, correlación positiva) en: %s\n",
              paste(sesgo_detectado$Operador, collapse = ", ")))
} else {
  cat("-> No se detectó evidencia estadísticamente significativa de sesgo favorito-longshot.\n")
}
cat("--------------------------------------------------\n")
cat("B) Apertura (PS) vs. Cierre (PSC):\n")
print(resumen_apertura_cierre)
if (resumen_apertura_cierre$Valor_p < 0.05 && resumen_apertura_cierre$Mejora_cierre_pct > 0) {
  cat("-> El cierre está significativamente mejor calibrado que la apertura.\n")
} else if (resumen_apertura_cierre$Valor_p >= 0.05) {
  cat("-> No hay diferencia estadísticamente significativa entre apertura y cierre.\n")
}
cat("====================================================\n")