# ============================================================
# Proyecto 2 - ¿Están bien calibradas las casas de apuestas?
# Fase 3: Evaluación de la calibración e inferencia estadística
# ============================================================
# Lee base_con_probabilidades.csv (Fase 2).
# Incluye:
# 1. Muestra común apareada (partidos con cuotas en todos los operadores)
# 2. Curvas de calibración con intervalos de Wilson (igual ancho e igual frecuencia)
# 3. Curvas desagregadas por resultado (H, D, A) y por liga (E0, SP1)
# 4. Reglas de puntuación: Brier Score vs. líneas base
# 5. BONIFICACIÓN (+2 pts): Descomposición de Murphy (Reliability, Resolution, Uncertainty)
# 6. BONIFICACIÓN (+2 pts): Ranked Probability Score (RPS) para mercado ordinal 1X2
# 7. Análisis de sensibilidad real de conclusiones (Multiplicativo vs. Aditivo vs. Shin)
# 8. Inferencia para datos apareados: Prueba global de Friedman y Wilcoxon apareado con ajuste de Holm
# 9. Prueba de Hosmer-Lemeshow SEPARADA POR RESULTADO (H/D/A), con justificación de
#    grados de libertad y reporte de magnitud
# ============================================================

source("config.R")

base <- fread(file.path(DIR_OUT, "base_con_probabilidades.csv"), encoding = "UTF-8")

# ---- 0. Muestra común apareada --------------------------------------
# Para que la comparación entre operadores sea formalmente válida y apareada,
# filtramos los partidos donde TODOS los operadores principales tienen datos
# completos de cuotas (evitando sesgos de selección muestral).
cond_comun <- rep(TRUE, nrow(base))
for (op in OPERADORES_PRINCIPALES) {
  colH <- paste0("pnorm_mult_", op, "_H")
  colD <- paste0("pnorm_mult_", op, "_D")
  colA <- paste0("pnorm_mult_", op, "_A")
  if (all(c(colH, colD, colA) %in% names(base))) {
    cond_comun <- cond_comun & (!is.na(base[[colH]]) & !is.na(base[[colD]]) & !is.na(base[[colA]]))
  }
}

base_comun <- base[cond_comun]
message(sprintf("Muestra común apareada construida: %d partidos (%.1f%% del total de %d)",
                nrow(base_comun), 100 * nrow(base_comun) / nrow(base), nrow(base)))

# Indicadores observados binarios
oH <- as.integer(base_comun$FTR == "H")
oD <- as.integer(base_comun$FTR == "D")
oA <- as.integer(base_comun$FTR == "A")

# ---- 1. Formato largo por operador y método -------------------------
construir_formato_largo <- function(dt, operador, metodo = "mult") {
  colH <- paste0("pnorm_", metodo, "_", operador, "_H")
  colD <- paste0("pnorm_", metodo, "_", operador, "_D")
  colA <- paste0("pnorm_", metodo, "_", operador, "_A")
  
  if (!all(c(colH, colD, colA) %in% names(dt))) return(NULL)
  
  largo <- rbindlist(list(
    dt[!is.na(get(colH)), .(Liga, Temporada, Resultado_evaluado = "H",
                            Prob_predicha = get(colH), Ocurrio = as.integer(FTR == "H"))],
    dt[!is.na(get(colD)), .(Liga, Temporada, Resultado_evaluado = "D",
                            Prob_predicha = get(colD), Ocurrio = as.integer(FTR == "D"))],
    dt[!is.na(get(colA)), .(Liga, Temporada, Resultado_evaluado = "A",
                            Prob_predicha = get(colA), Ocurrio = as.integer(FTR == "A"))]
  ))
  largo[, `:=`(Operador = operador, Metodo = metodo)]
  largo
}

# Formato largo principal (Multiplicativo)
datos_largos_mult <- rbindlist(lapply(OPERADORES_PRINCIPALES, construir_formato_largo,
                                      dt = base_comun, metodo = "mult"))

# Formatos largos alternativos para sensibilidad
datos_largos_adit <- rbindlist(lapply(OPERADORES_PRINCIPALES, construir_formato_largo,
                                      dt = base_comun, metodo = "adit"))
datos_largos_shin <- rbindlist(lapply(OPERADORES_PRINCIPALES, construir_formato_largo,
                                      dt = base_comun, metodo = "shin"))

# [FIX] Diagnóstico explícito de filas excluidas por no convergencia de Shin.
# normalizar_shin() (Fase 2) devuelve NA cuando uniroot no converge o la cuota
# bruta es <=0. construir_formato_largo() ya descarta esas filas NA al armar
# el formato largo, pero aquí lo reportamos explícitamente para que quede
# documentado cuántos partidos se pierden por operador al usar Shin.
resumen_na_shin <- rbindlist(lapply(OPERADORES_PRINCIPALES, function(op) {
  colH <- paste0("pnorm_shin_", op, "_H")
  if (!colH %in% names(base_comun)) return(NULL)
  data.table(
    Operador = op,
    N_total = nrow(base_comun),
    N_excluidos_shin_NA = sum(is.na(base_comun[[colH]])),
    Pct_excluidos = round(100 * sum(is.na(base_comun[[colH]])) / nrow(base_comun), 2)
  )
}))
message("\n---- Filas excluidas por no convergencia de Shin (por operador) ----")
print(resumen_na_shin)

# ---- 2. Curvas de calibración con intervalos de Wilson --------------
construir_curva_calibracion <- function(dt, n_bins = N_BINS, esquema = "igual_ancho", grupo_vars = c("Operador")) {
  d <- copy(dt)
  if (esquema == "igual_ancho") {
    d[, bin := cut(Prob_predicha, breaks = seq(0, 1, length.out = n_bins + 1),
                   include.lowest = TRUE, labels = FALSE)]
  } else if (esquema == "igual_frecuencia") {
    d[, bin := cut(rank(Prob_predicha, ties.method = "first"),
                   breaks = n_bins, include.lowest = TRUE, labels = FALSE)]
  } else {
    stop("esquema debe ser 'igual_ancho' o 'igual_frecuencia'")
  }
  
  vars_agrup <- c(grupo_vars, "bin")
  curva <- d[, {
    n <- .N
    aciertos <- sum(Ocurrio)
    ic <- binom::binom.confint(aciertos, n, methods = "wilson")
    .(
      Prob_predicha_media = mean(Prob_predicha),
      Frecuencia_observada = aciertos / n,
      IC_inferior = ic$lower,
      IC_superior = ic$upper,
      N = n
    )
  }, by = vars_agrup]
  
  curva[, Desviacion_pp := 100 * (Frecuencia_observada - Prob_predicha_media)]
  setorderv(curva, vars_agrup)
  curva
}

curva_igual_ancho <- construir_curva_calibracion(datos_largos_mult, N_BINS, "igual_ancho", "Operador")
curva_igual_frec  <- construir_curva_calibracion(datos_largos_mult, N_BINS, "igual_frecuencia", "Operador")

# Curvas desagregadas por resultado (H, D, A)
curva_por_resultado <- construir_curva_calibracion(datos_largos_mult, N_BINS, "igual_ancho",
                                                   c("Operador", "Resultado_evaluado"))

# Curvas desagregadas por liga (E0, SP1)
curva_por_liga <- construir_curva_calibracion(datos_largos_mult, N_BINS, "igual_ancho",
                                              c("Operador", "Liga"))

message("\n---- Curva de calibración general (igual ancho, 10 bins) ----")
print(curva_igual_ancho)

# ---- 3. Reglas de puntuación: Brier Score vs. Líneas Base -----------
# [FIX] Se agrega na.rm = TRUE en los tres mean(): sin esto, si Shin no
# converge aunque sea en una sola fila, el promedio del operador completo
# sale NA de forma silenciosa, sin ningún aviso en consola.
calcular_brier_completo <- function(dt, operador, metodo = "mult") {
  colH <- paste0("pnorm_", metodo, "_", operador, "_H")
  colD <- paste0("pnorm_", metodo, "_", operador, "_D")
  colA <- paste0("pnorm_", metodo, "_", operador, "_A")
  
  pH <- dt[[colH]]; pD <- dt[[colD]]; pA <- dt[[colA]]
  
  brier_partido <- (pH - oH)^2 + (pD - oD)^2 + (pA - oA)^2
  n_validos <- sum(!is.na(brier_partido))
  brier_op <- mean(brier_partido, na.rm = TRUE)  # [FIX]
  
  # Líneas base (siempre sobre la base completa, no dependen del método)
  fH <- mean(oH); fD <- mean(oD); fA <- mean(oA)
  brier_base_frec <- mean((fH - oH)^2 + (fD - oD)^2 + (fA - oA)^2)
  brier_base_unif <- mean((1/3 - oH)^2 + (1/3 - oD)^2 + (1/3 - oA)^2)
  
  data.table(
    Operador = operador,
    Metodo = metodo,
    N_partidos = n_validos,  # [FIX] N real usado, no nrow(dt) completo
    Brier_operador = round(brier_op, 4),
    Brier_linea_base_frecuencia = round(brier_base_frec, 4),
    Brier_linea_base_uniforme = round(brier_base_unif, 4),
    Mejora_vs_frecuencia_pct = round(100 * (brier_base_frec - brier_op) / brier_base_frec, 2),
    Mejora_vs_uniforme_pct = round(100 * (brier_base_unif - brier_op) / brier_base_unif, 2)
  )
}

tabla_brier <- rbindlist(lapply(OPERADORES_PRINCIPALES, calcular_brier_completo,
                                dt = base_comun, metodo = "mult"))
message("\n---- Brier Score por operador (Muestra común, Multiplicativo) ----")
print(tabla_brier)

# ---- 4. BONIFICACIÓN (+2 pts): Descomposición de Murphy del Brier ----
# Brier multiclase = Reliability - Resolution + Uncertainty
# Para cada resultado binario j in {H, D, A}:
#   UNC_j = bar_o_j * (1 - bar_o_j)
#   REL_j = sum_k (n_k / N) * (bar_p_jk - bar_o_jk)^2
#   RES_j = sum_k (n_k / N) * (bar_o_jk - bar_o_j)^2
#   Brier_j = REL_j - RES_j + UNC_j
# [FIX] Se filtran los NA de prob/observacion antes de calcular N y bar_o,
# por la misma razón que en la sección 3 (filas Shin no convergentes).
descomposicion_murphy <- function(prob, observacion, n_bins = 10) {
  validos <- !is.na(prob) & !is.na(observacion)
  prob <- prob[validos]
  observacion <- observacion[validos]
  
  N <- length(prob)  # [FIX] ahora es el N ya filtrado, no el N bruto original
  bar_o <- mean(observacion)
  unc <- bar_o * (1 - bar_o)
  
  bins <- cut(prob, breaks = seq(0, 1, length.out = n_bins + 1), include.lowest = TRUE, labels = FALSE)
  df_bin <- data.table(p = prob, o = observacion, bin = bins)[, .(
    n = .N,
    bar_p = mean(p),
    bar_o_k = mean(o)
  ), by = bin]
  
  rel <- sum((df_bin$n / N) * (df_bin$bar_p - df_bin$bar_o_k)^2)
  res <- sum((df_bin$n / N) * (df_bin$bar_o_k - bar_o)^2)
  brier <- rel - res + unc
  
  list(Reliability = rel, Resolution = res, Uncertainty = unc, Brier = brier)
}

calcular_murphy_operador <- function(dt, operador, metodo = "mult") {
  colH <- paste0("pnorm_", metodo, "_", operador, "_H")
  colD <- paste0("pnorm_", metodo, "_", operador, "_D")
  colA <- paste0("pnorm_", metodo, "_", operador, "_A")
  
  mH <- descomposicion_murphy(dt[[colH]], oH, N_BINS)
  mD <- descomposicion_murphy(dt[[colD]], oD, N_BINS)
  mA <- descomposicion_murphy(dt[[colA]], oA, N_BINS)
  
  # Suma multiclase
  rel_total <- mH$Reliability + mD$Reliability + mA$Reliability
  res_total <- mH$Resolution + mD$Resolution + mA$Resolution
  unc_total <- mH$Uncertainty + mD$Uncertainty + mA$Uncertainty
  brier_total <- rel_total - res_total + unc_total
  
  data.table(
    Operador = operador,
    Metodo = metodo,
    Fiabilidad_Reliability = round(rel_total, 5),
    Resolucion_Resolution = round(res_total, 5),
    Incertidumbre_Uncertainty = round(unc_total, 5),
    Brier_calculado = round(brier_total, 4)
  )
}

tabla_murphy <- rbindlist(lapply(OPERADORES_PRINCIPALES, calcular_murphy_operador,
                                 dt = base_comun, metodo = "mult"))
message("\n---- BONIFICACIÓN: Descomposición de Murphy del Brier ----")
print(tabla_murphy)
message("Nota metodológica: Fiabilidad mide descalibramiento (cercano a 0 es ideal);")
message("Resolución mide capacidad discriminativa (mayor es mejor); Incertidumbre es constante.")

# ---- 5. BONIFICACIÓN (+2 pts): Ranked Probability Score (RPS) --------
# El RPS penaliza más fuerte los pronósticos alejados del resultado en la escala
# ordenada natural: Victoria Local (H) <-> Empate (D) <-> Victoria Visitante (A).
# RPS = 0.5 * [ (p_H - o_H)^2 + ((p_H + p_D) - (o_H + o_D))^2 ]
# [FIX] na.rm = TRUE en el promedio final, misma razón que en Brier.
calcular_rps_operador <- function(dt, operador, metodo = "mult") {
  colH <- paste0("pnorm_", metodo, "_", operador, "_H")
  colD <- paste0("pnorm_", metodo, "_", operador, "_D")
  colA <- paste0("pnorm_", metodo, "_", operador, "_A")
  
  pH <- dt[[colH]]; pD <- dt[[colD]]; pA <- dt[[colA]]
  
  # Función acumulada
  P1 <- pH; O1 <- oH
  P2 <- pH + pD; O2 <- oH + oD
  
  rps_partido <- 0.5 * ((P1 - O1)^2 + (P2 - O2)^2)
  rps_op <- mean(rps_partido, na.rm = TRUE)  # [FIX]
  
  # Líneas base RPS
  fH <- mean(oH); fD <- mean(oD)
  rps_base_frec <- mean(0.5 * ((fH - oH)^2 + ((fH + fD) - (oH + oD))^2))
  rps_base_unif <- mean(0.5 * ((1/3 - oH)^2 + ((2/3) - (oH + oD))^2))
  
  data.table(
    Operador = operador,
    Metodo = metodo,
    RPS_operador = round(rps_op, 4),
    RPS_linea_base_frecuencia = round(rps_base_frec, 4),
    RPS_linea_base_uniforme = round(rps_base_unif, 4),
    Mejora_vs_frecuencia_pct = round(100 * (rps_base_frec - rps_op) / rps_base_frec, 2),
    Mejora_vs_uniforme_pct = round(100 * (rps_base_unif - rps_op) / rps_base_unif, 2)
  )
}

tabla_rps <- rbindlist(lapply(OPERADORES_PRINCIPALES, calcular_rps_operador,
                              dt = base_comun, metodo = "mult"))
message("\n---- BONIFICACIÓN: Ranked Probability Score (RPS) ----")
print(tabla_rps)

# ---- 6. Sensibilidad real de conclusiones entre métodos --------------
# Compara cómo cambian Brier, RPS, Fiabilidad de Murphy y Desviación media
# al pasar de Multiplicativo -> Aditivo -> Shin.
sensibilidad_conclusiones <- rbindlist(lapply(c("mult", "adit", "shin"), function(met) {
  res <- rbindlist(lapply(OPERADORES_PRINCIPALES, function(op) {
    colH <- paste0("pnorm_", met, "_", op, "_H")
    if (!colH %in% names(base_comun)) return(NULL)
    
    br <- calcular_brier_completo(base_comun, op, met)
    rp <- calcular_rps_operador(base_comun, op, met)
    mu <- calcular_murphy_operador(base_comun, op, met)
    
    dt_largo_tmp <- construir_formato_largo(base_comun, op, met)
    curva_tmp <- construir_curva_calibracion(dt_largo_tmp, N_BINS, "igual_ancho", "Operador")
    desv_med <- round(mean(abs(curva_tmp$Desviacion_pp)), 2)
    
    data.table(
      Operador = op,
      Metodo = met,
      Brier = br$Brier_operador,
      RPS = rp$RPS_operador,
      Fiabilidad_Murphy = mu$Fiabilidad_Reliability,
      Desviacion_media_abs_pp = desv_med
    )
  }))
  res
}))

message("\n---- Sensibilidad de conclusiones entre métodos (Mult vs Adit vs Shin) ----")
print(sensibilidad_conclusiones)

# ---- 7. Pruebas apareadas entre operadores (Muestra Común) ----------
# Como todos los operadores cotizan sobre los mismos partidos, aplicamos:
# a) Prueba global de Friedman (medidas repetidas no paramétricas)
# b) Pruebas de Wilcoxon apareadas con corrección de Holm por comparaciones múltiples.
# Nota: esta sección usa pnorm_mult_*, que por construcción de cond_comun (sección 0)
# no tiene NA en la muestra común, así que no requiere los ajustes na.rm anteriores.
matriz_brier <- sapply(OPERADORES_PRINCIPALES, function(op) {
  pH <- base_comun[[paste0("pnorm_mult_", op, "_H")]]
  pD <- base_comun[[paste0("pnorm_mult_", op, "_D")]]
  pA <- base_comun[[paste0("pnorm_mult_", op, "_A")]]
  (pH - oH)^2 + (pD - oD)^2 + (pA - oA)^2
})

# Prueba global de Friedman
test_friedman <- friedman.test(matriz_brier)
message("\n---- Prueba global de Friedman entre operadores (datos apareados) ----")
cat(sprintf("Chi-cuadrado Friedman = %.2f, gl = %d, Valor-p = %g\n",
            test_friedman$statistic, test_friedman$parameter, test_friedman$p.value))

# Pruebas apareadas por pares con corrección de Holm
pares <- combn(OPERADORES_PRINCIPALES, 2, simplify = FALSE)
comparaciones_apareadas <- rbindlist(lapply(pares, function(par) {
  op1 <- par[1]; op2 <- par[2]
  brier1 <- matriz_brier[, op1]
  brier2 <- matriz_brier[, op2]
  
  test_w <- wilcox.test(brier1, brier2, paired = TRUE)
  diff_media <- mean(brier1) - mean(brier2)
  
  data.table(
    Comparacion = sprintf("%s vs %s", op1, op2),
    Brier_Op1 = round(mean(brier1), 4),
    Brier_Op2 = round(mean(brier2), 4),
    Dif_Brier = round(diff_media, 5),
    Mejora_pct = round(100 * -diff_media / mean(brier2), 2),
    Wilcoxon_V = unname(test_w$statistic),
    Valor_p_crudo = test_w$p.value
  )
}))

comparaciones_apareadas[, Valor_p_ajustado_Holm := p.adjust(Valor_p_crudo, method = "holm")]
comparaciones_apareadas[, Significativo_Holm_0.05 := Valor_p_ajustado_Holm < 0.05]

message("\n---- Comparaciones apareadas por pares (Wilcoxon + corrección de Holm) ----")
print(comparaciones_apareadas[, .(Comparacion, Dif_Brier, Mejora_pct,
                                  Valor_p_crudo = signif(Valor_p_crudo, 4),
                                  Valor_p_ajustado_Holm = signif(Valor_p_ajustado_Holm, 4),
                                  Significativo_Holm_0.05)])

# ---- 8. Prueba de Hosmer-Lemeshow SEPARADA POR RESULTADO ------------
# [FIX - ARREGLO RESTAURADO] Cada partido aporta 3 filas al formato largo
# (H, D, A), que NO son independientes entre sí (si ocurrió H, no ocurrieron
# D ni A). Agrupar las tres en el mismo test de bondad de ajuste viola el
# supuesto de independencia del chi-cuadrado. Por eso el test se corre POR
# SEPARADO para cada resultado: dentro de una sola categoría (ej. "H"), cada
# partido aporta exactamente una fila, así que ahí sí son observaciones
# independientes entre partidos (la dependencia más amplia entre partidos de
# la misma temporada/jornada queda como limitación declarada, no resuelta
# por este cambio).
#
# Grados de libertad: se usa gl = n_bins - 1. La regla clásica gl = g - 2
# viene de Hosmer-Lemeshow aplicado a un modelo logístico, donde se restan
# 2 parámetros estimados sobre la misma muestra (intercepto y pendiente).
# Aquí las probabilidades son EXÓGENAS (provienen del mercado, no de un
# modelo ajustado a estos datos), así que no corresponde restar esos 2
# parámetros. Se usa g - 1 en vez de g porque los recuentos de observados
# y predichos por bin están sujetos a una restricción de suma global
# (la cuenta total de partidos). Esta elección se documenta explícitamente
# en el informe, ya que no hay un único estándar universal para este caso.
prueba_hosmer_lemeshow <- function(dt_largo, operador, resultado, n_bins = N_BINS) {
  d <- dt_largo[Operador == operador & Resultado_evaluado == resultado]  # [FIX] filtro por resultado restaurado
  d[, bin := cut(Prob_predicha, breaks = seq(0, 1, length.out = n_bins + 1),
                 include.lowest = TRUE, labels = FALSE)]
  
  resumen <- d[, .(
    N = .N,
    Observado = sum(Ocurrio),
    Predicho = sum(Prob_predicha)
  ), by = bin]
  
  resumen[, chi2_termino := (Observado - Predicho)^2 / (Predicho * (1 - Predicho / N))]
  resumen[, Desviacion_pp := 100 * (Observado / N - Predicho / N)]
  
  estadistico <- sum(resumen$chi2_termino, na.rm = TRUE)
  gl <- n_bins - 1
  p_valor <- pchisq(estadistico, df = gl, lower.tail = FALSE)
  
  data.table(
    Operador = operador,
    Resultado = resultado,  # [FIX] columna restaurada
    Estadistico_HL = round(estadistico, 2),
    Grados_libertad = gl,
    Valor_p = signif(p_valor, 4),
    Rechaza_calibracion_perfecta_0.05 = p_valor < 0.05,
    Desviacion_media_abs_pp = round(mean(abs(resumen$Desviacion_pp)), 2)
  )
}

combinaciones_hl <- CJ(Operador = OPERADORES_PRINCIPALES, Resultado = c("H", "D", "A"))  # [FIX] restaurado

tabla_hl <- rbindlist(mapply(
  prueba_hosmer_lemeshow,
  operador = combinaciones_hl$Operador,
  resultado = combinaciones_hl$Resultado,
  MoreArgs = list(dt_largo = datos_largos_mult),
  SIMPLIFY = FALSE
))

# [FIX] Corrección por comparaciones múltiples: 12 pruebas (4 operadores
# x 3 resultados) evaluadas en conjunto. Se ajusta con Holm, mismo método
# ya usado en la sección 7 para las comparaciones entre operadores.

tabla_hl[, Valor_p_ajustado_Holm := p.adjust(Valor_p, method = "holm")]
tabla_hl[, Significativo_Holm_0.05 := Valor_p_ajustado_Holm < 0.05]

message("\n---- Hosmer-Lemeshow separado por resultado (H/D/A), gl = K - 1 ----")
print(tabla_hl[, .(Operador, Resultado, Valor_p, Valor_p_ajustado_Holm,
                   Significativo_Holm_0.05, Desviacion_media_abs_pp)])
message("\nRECORDATORIO: un valor_p significativo NO implica que la desviación")
message("importe en la práctica. Revisa siempre Desviacion_media_abs_pp junto al p-valor.")
message("RECORDATORIO 2: con 12 pruebas (4 operadores x 3 resultados), considerar")
message("corrección por comparaciones múltiples al interpretar significancia conjunta.")

# ---- 9. Sensibilidad al esquema de agrupamiento ---------------------
comparar_esquemas <- function() {
  resultados <- list()
  for (esquema in c("igual_ancho", "igual_frecuencia")) {
    for (nb in c(5, 10, 20)) {
      curva_tmp <- construir_curva_calibracion(datos_largos_mult, nb, esquema, "Operador")
      resumen <- curva_tmp[, .(
        Esquema = esquema, N_bins = nb,
        Desviacion_media_abs_pp = round(mean(abs(Desviacion_pp)), 2)
      ), by = Operador]
      resultados[[length(resultados) + 1]] <- resumen
    }
  }
  rbindlist(resultados)
}

sensibilidad_agrupamiento <- comparar_esquemas()

# ---- 10. Guardar salidas --------------------------------------------
fwrite(curva_igual_ancho, file.path(DIR_OUT, "curva_calibracion_igual_ancho.csv"))
fwrite(curva_igual_frec, file.path(DIR_OUT, "curva_calibracion_igual_frecuencia.csv"))
fwrite(curva_por_resultado, file.path(DIR_OUT, "curva_calibracion_por_resultado.csv"))
fwrite(curva_por_liga, file.path(DIR_OUT, "curva_calibracion_por_liga.csv"))
fwrite(tabla_brier, file.path(DIR_OUT, "brier_score.csv"))
fwrite(tabla_murphy, file.path(DIR_OUT, "descomposicion_murphy.csv"))
fwrite(tabla_rps, file.path(DIR_OUT, "rps_score.csv"))
fwrite(sensibilidad_conclusiones, file.path(DIR_OUT, "sensibilidad_conclusiones_metodos.csv"))
fwrite(comparaciones_apareadas, file.path(DIR_OUT, "comparacion_apareada_operadores.csv"))
fwrite(tabla_hl, file.path(DIR_OUT, "hosmer_lemeshow.csv"))
fwrite(sensibilidad_agrupamiento, file.path(DIR_OUT, "sensibilidad_agrupamiento.csv"))
fwrite(resumen_na_shin, file.path(DIR_OUT, "shin_no_convergencia.csv"))  # [FIX] nuevo output de trazabilidad

message("\nListo. Todos los archivos de la Fase 3 guardados en outputs/:")
message(" - curva_calibracion_igual_ancho.csv")
message(" - curva_calibracion_igual_frecuencia.csv")
message(" - curva_calibracion_por_resultado.csv")
message(" - curva_calibracion_por_liga.csv")
message(" - brier_score.csv")
message(" - descomposicion_murphy.csv (BONIFICACIÓN)")
message(" - rps_score.csv (BONIFICACIÓN)")
message(" - sensibilidad_conclusiones_metodos.csv")
message(" - comparacion_apareada_operadores.csv")
message(" - hosmer_lemeshow.csv (separado por H/D/A)")
message(" - sensibilidad_agrupamiento.csv")
message(" - shin_no_convergencia.csv")

# ---- 11. Resumen final consolidado ----------------------------------
mostrar_resumen_fase3 <- function() {
  cat("\n")
  cat("================ RESUMEN FASE 3 (CALIBRACIÓN E INFERENCIA) ================\n")
  cat(sprintf("Muestra común apareada:           %d partidos evaluados simultáneamente\n", nrow(base_comun)))
  cat(sprintf("Operadores principales:           %s\n", paste(OPERADORES_PRINCIPALES, collapse = ", ")))
  cat("--------------------------------------------------------------------------\n")
  cat("Brier Score y RPS vs. Líneas Base (Muestra Común):\n")
  comp_metr <- merge(tabla_brier[, .(Operador, Brier = Brier_operador, Mejora_Brier = Mejora_vs_frecuencia_pct)],
                     tabla_rps[, .(Operador, RPS = RPS_operador, Mejora_RPS = Mejora_vs_frecuencia_pct)],
                     by = "Operador")
  print(comp_metr)
  cat("--------------------------------------------------------------------------\n")
  cat("Bonificación Murphy (Brier = Fiabilidad - Resolución + Incertidumbre):\n")
  print(tabla_murphy[, .(Operador, Fiabilidad_Reliability, Resolucion_Resolution, Incertidumbre_Uncertainty)])
  cat("--------------------------------------------------------------------------\n")
  cat("Sensibilidad metodológica (Brier y Desviación por método de margen):\n")
  print(sensibilidad_conclusiones[, .(Operador, Metodo, Brier, RPS, Desviacion_media_abs_pp)])
  cat("--------------------------------------------------------------------------\n")
  cat("Inferencia Apareada (Friedman y contrastes pareados con ajuste Holm):\n")
  cat(sprintf("  Friedman p-valor = %g\n", test_friedman$p.value))
  print(comparaciones_apareadas[, .(Comparacion, Dif_Brier, Mejora_pct, Valor_p_ajustado_Holm, Significativo_Holm_0.05)])
  cat("--------------------------------------------------------------------------\n")
  cat("Hosmer-Lemeshow por resultado (12 pruebas: 4 operadores x H/D/A):\n")
  print(tabla_hl[, .(Operador, Resultado, Valor_p, Valor_p_ajustado_Holm, Significativo_Holm_0.05, Desviacion_media_abs_pp)])
  cat("==========================================================================\n")
}

mostrar_resumen_fase3()
