#Fase 3 - Evaluación de la calibración

library(data.table)

paquetes <- c("binom")
instalar_faltantes <- paquetes[!paquetes %in% rownames(installed.packages())]
if (length(instalar_faltantes) > 0) install.packages(instalar_faltantes)
library(binom)

DIR_OUT <- "outputs"
base <- fread(file.path(DIR_OUT, "base_con_probabilidades.csv"), encoding = "UTF-8")

# ---- 0. Parámetros ------------------------------------------------
OPERADORES_PRINCIPALES <- c("B365", "PS", "PSC", "WH")
N_BINS <- 10  # esquema principal: 10 intervalos de igual ancho

# ---- 1. Construir formato "largo" (pooled) por operador -----------
# Para cada operador y cada partido, generamos 3 filas: una por
# resultado (H, D, A), con la probabilidad normalizada (multiplicativa)
# que el operador le asignó y un indicador binario de si ocurrió.
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
message(sprintf("Formato largo construido: %d observaciones (partidos x 3 resultados x %d operadores)",
                nrow(datos_largos), length(OPERADORES_PRINCIPALES)))

# ---- 2. Curva de calibración con intervalos de Wilson --------------
# Agrupa en N_BINS intervalos de igual ancho [0,1], calcula la
# probabilidad media predicha y la frecuencia observada (con IC de
# Wilson) en cada intervalo.
construir_curva_calibracion <- function(dt, n_bins = N_BINS, esquema = "igual_ancho") {
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
  
  curva <- d[, {
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
  }, by = .(Operador, bin)]
  
  curva[, Desviacion_pp := 100 * (Frecuencia_observada - Prob_predicha_media)]
  setorder(curva, Operador, bin)
  curva
}

curva_igual_ancho <- construir_curva_calibracion(datos_largos, N_BINS, "igual_ancho")
curva_igual_frec  <- construir_curva_calibracion(datos_largos, N_BINS, "igual_frecuencia")

message("\n---- Curva de calibración (esquema principal: igual ancho) ----")
print(curva_igual_ancho)

# ---- 3. Reglas de puntuación: Brier score contra líneas base -------
# Brier multiclase por partido: suma de (p_i - o_i)^2 sobre los 3
# resultados, donde o_i es 1 si ocurrió ese resultado y 0 si no.
# Se compara contra dos líneas base:
#   a) "Frecuencia histórica": predecir siempre la frecuencia
#      histórica observada de H/D/A en la muestra (constante).
#   b) "Uniforme": predecir siempre 1/3 para cada resultado.
calcular_brier_operador <- function(dt, operador) {
  colH <- paste0("pnorm_mult_", operador, "_H")
  colD <- paste0("pnorm_mult_", operador, "_D")
  colA <- paste0("pnorm_mult_", operador, "_A")
  
  sub <- dt[!is.na(get(colH)) & !is.na(get(colD)) & !is.na(get(colA))]
  
  oH <- as.integer(sub$FTR == "H")
  oD <- as.integer(sub$FTR == "D")
  oA <- as.integer(sub$FTR == "A")
  
  brier_operador <- mean((sub[[colH]] - oH)^2 + (sub[[colD]] - oD)^2 + (sub[[colA]] - oA)^2)
  
  freq_H <- mean(oH); freq_D <- mean(oD); freq_A <- mean(oA)
  brier_frecuencia <- mean((freq_H - oH)^2 + (freq_D - oD)^2 + (freq_A - oA)^2)
  
  brier_uniforme <- mean((1/3 - oH)^2 + (1/3 - oD)^2 + (1/3 - oA)^2)
  
  data.table(
    Operador = operador,
    N_partidos = nrow(sub),
    Brier_operador = round(brier_operador, 4),
    Brier_linea_base_frecuencia = round(brier_frecuencia, 4),
    Brier_linea_base_uniforme = round(brier_uniforme, 4),
    Mejora_vs_frecuencia_pct = round(100 * (brier_frecuencia - brier_operador) / brier_frecuencia, 1),
    Mejora_vs_uniforme_pct = round(100 * (brier_uniforme - brier_operador) / brier_uniforme, 1)
  )
}

tabla_brier <- rbindlist(lapply(OPERADORES_PRINCIPALES, calcular_brier_operador, dt = base))
message("\n---- Brier score por operador, contra líneas base ----")
print(tabla_brier)
message("\nInterpretación: Brier_operador MENOR que las líneas base = el operador")
message("predice mejor que simplemente usar la frecuencia histórica o 1/3-1/3-1/3.")
message("Mejora_vs_*_pct > 0 significa que el operador es mejor que esa línea base.")

# ---- 4. Prueba de bondad de ajuste (tipo Hosmer-Lemeshow) -----------
# Implementación manual sobre los mismos bins de la curva de
# calibración (igual ancho): estadístico chi-cuadrado de Hosmer-
# Lemeshow, comparando frecuencia observada vs. predicha en cada bin.
# ADVERTENCIA (explícita en el enunciado): con decenas de miles de
# observaciones, esta prueba casi siempre rechaza la calibración
# perfecta aunque la desviación sea mínima. Por eso SIEMPRE se reporta
# junto con la magnitud de la desviación en puntos porcentuales
# (ya calculada en la curva de calibración, columna Desviacion_pp).
prueba_hosmer_lemeshow <- function(dt_largo, operador, n_bins = N_BINS) {
  d <- dt_largo[Operador == operador]
  d[, bin := cut(Prob_predicha, breaks = seq(0, 1, length.out = n_bins + 1),
                 include.lowest = TRUE, labels = FALSE)]
  
  resumen <- d[, .(
    N = .N,
    Observado = sum(Ocurrio),
    Predicho = sum(Prob_predicha)
  ), by = bin]
  
  # Estadístico chi-cuadrado de Hosmer-Lemeshow
  resumen[, chi2_termino := (Observado - Predicho)^2 / (Predicho * (1 - Predicho / N))]
  estadistico <- sum(resumen$chi2_termino, na.rm = TRUE)
  gl <- n_bins - 2  # grados de libertad estándar de HL
  p_valor <- pchisq(estadistico, df = gl, lower.tail = FALSE)
  
  data.table(
    Operador = operador,
    Estadistico_HL = round(estadistico, 2),
    Grados_libertad = gl,
    Valor_p = signif(p_valor, 4),
    Rechaza_calibracion_perfecta_0.05 = p_valor < 0.05
  )
}

tabla_hl <- rbindlist(lapply(OPERADORES_PRINCIPALES, prueba_hosmer_lemeshow, dt_largo = datos_largos))

# Cruzar con la magnitud media de desviación (en pp) de cada operador,
# para no reportar el p-valor solo (penalizado en la rúbrica: -5 pts).
magnitud_media <- curva_igual_ancho[, .(Desviacion_media_abs_pp = round(mean(abs(Desviacion_pp)), 2)),
                                    by = Operador]
tabla_hl <- merge(tabla_hl, magnitud_media, by = "Operador")

message("\n---- Prueba de bondad de ajuste (Hosmer-Lemeshow) + magnitud de la desviación ----")
print(tabla_hl)
message("\nRECORDATORIO: un valor_p significativo NO implica que la desviación")
message("importe en la práctica. Revisa siempre Desviacion_media_abs_pp junto al p-valor.")

# ---- 5. Sensibilidad al esquema de agrupamiento ---------------------
# Compara la desviación media (en pp) obtenida con 10 intervalos de
# igual ancho vs. 10 intervalos de igual frecuencia, y también con
# un número distinto de intervalos (5 y 20), para verificar que las
# conclusiones no dependan de estas elecciones.
comparar_esquemas <- function() {
  resultados <- list()
  for (esquema in c("igual_ancho", "igual_frecuencia")) {
    for (nb in c(5, 10, 20)) {
      curva_tmp <- construir_curva_calibracion(datos_largos, nb, esquema)
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
message("\n---- Sensibilidad al esquema de agrupamiento (igual ancho vs. igual frecuencia, 5/10/20 bins) ----")
print(sensibilidad_agrupamiento)

# ---- 6. Guardar salidas ---------------------------------------------
fwrite(curva_igual_ancho, file.path(DIR_OUT, "curva_calibracion_igual_ancho.csv"))
fwrite(curva_igual_frec, file.path(DIR_OUT, "curva_calibracion_igual_frecuencia.csv"))
fwrite(tabla_brier, file.path(DIR_OUT, "brier_score.csv"))
fwrite(tabla_hl, file.path(DIR_OUT, "hosmer_lemeshow.csv"))
fwrite(sensibilidad_agrupamiento, file.path(DIR_OUT, "sensibilidad_agrupamiento.csv"))

message("\nListo. Archivos guardados en data/processed/:")
message(" - curva_calibracion_igual_ancho.csv")
message(" - curva_calibracion_igual_frecuencia.csv")
message(" - brier_score.csv")
message(" - hosmer_lemeshow.csv")
message(" - sensibilidad_agrupamiento.csv")

# ---- 7. Resumen final (para copiar y revisar de un vistazo) ---------
mostrar_resumen_fase3 <- function() {
  cat("\n")
  cat("================ RESUMEN FASE 3 ================\n")
  cat(sprintf("Operadores analizados: %s\n", paste(OPERADORES_PRINCIPALES, collapse = ", ")))
  cat(sprintf("Observaciones (pooled, partido x resultado): %d\n", nrow(datos_largos)))
  cat("--------------------------------------------------\n")
  cat("Brier score (menor es mejor) vs. líneas base:\n")
  print(tabla_brier[, .(Operador, Brier_operador, Mejora_vs_frecuencia_pct, Mejora_vs_uniforme_pct)])
  cat("--------------------------------------------------\n")
  cat("Hosmer-Lemeshow + magnitud de la desviación:\n")
  print(tabla_hl[, .(Operador, Valor_p, Rechaza_calibracion_perfecta_0.05, Desviacion_media_abs_pp)])
  cat("--------------------------------------------------\n")
  dif_esquemas <- sensibilidad_agrupamiento[, .(
    Rango_desviacion_pp = round(max(Desviacion_media_abs_pp) - min(Desviacion_media_abs_pp), 2)
  ), by = Operador]
  cat("Sensibilidad al esquema de agrupamiento (rango de desviación entre todos los esquemas probados):\n")
  print(dif_esquemas)
  if (all(dif_esquemas$Rango_desviacion_pp < 1)) {
    cat("-> Rango pequeño en todos los operadores: la conclusión NO depende del esquema elegido.\n")
  } else {
    cat("-> Algún operador muestra sensibilidad notable al esquema: reportarlo como limitación.\n")
  }
  cat("====================================================\n")
}

mostrar_resumen_fase3()