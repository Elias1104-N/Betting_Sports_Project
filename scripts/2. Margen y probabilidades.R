# ============================================================
# Proyecto 2 - ¿Están bien calibradas las casas de apuestas?
# Fase 2: De cuotas a probabilidades - el tratamiento del margen
# ============================================================
# Parte de base_consolidada.csv (generado en la Fase 1).
# Calcula probabilidades brutas, el margen del operador, y aplica
# al menos dos métodos de remoción del margen (requisito de la
# rúbrica, criterio C). Documenta la distribución del margen y
# compara qué tanto cambian las conclusiones entre métodos
# (análisis de sensibilidad).
# ============================================================

source("config.R")

base <- fread(file.path(DIR_OUT, "base_consolidada.csv"), encoding = "UTF-8")

# ---- 0. Identificar qué operadores tenemos ----------------------
# Un "operador" es cualquier prefijo de columna con las 3 columnas
# H/D/A completas (ej. B365H/B365D/B365A, o OddHomeB365/... si vienes
# de la fuente alterna - ajusta el patrón según tus nombres reales).
cols_todas <- names(base)

# Detecta automáticamente prefijos candidatos a "operador" buscando
# columnas que terminen en H, D o A y que tengan su trío completo.
sufijos <- c("H", "D", "A")
prefijos_candidatos <- unique(gsub("(H|D|A)$", "", grep("(H|D|A)$", cols_todas, value = TRUE)))
prefijos_candidatos <- setdiff(prefijos_candidatos, c("FTHG","FTAG","HTHG","HTAG","FT","HT"))

operadores <- prefijos_candidatos[
  sapply(prefijos_candidatos, function(p) all(paste0(p, sufijos) %in% cols_todas))
]

if (length(operadores) == 0) {
  stop("No se detectaron columnas de cuotas con el patrón esperado (PrefijoH/D/A). Revisa los nombres de columnas de tu base.")
}

# 0.1 Separar operadores REALES (una casa de apuestas específica)
# de AGREGADOS DE MERCADO (Max/Avg y sus variantes de cierre "...C").
# Estos últimos toman, para cada resultado por separado, el máximo o
# promedio entre varias casas - no son el precio de ningún operador
# individual, así que su "margen" calculado no es comparable al de
# un operador real (puede salir artificialmente bajo o negativo).
# El propio enunciado del proyecto los describe como "útiles como
# referencia agregada", no como una casa más a comparar en la Fase 4.
patron_agregado <- "^(Max|Avg|BbMx|BbAv|BbOU|BbAH)"
es_agregado <- grepl(patron_agregado, operadores, ignore.case = TRUE)

operadores_agregado <- operadores[es_agregado]
operadores_reales   <- operadores[!es_agregado]

message(sprintf("Operadores detectados (%d en total):", length(operadores)))
message(sprintf("  - Casas de apuestas reales (%d): %s",
                length(operadores_reales), paste(operadores_reales, collapse = ", ")))
message(sprintf("  - Agregados de mercado (%d, tratados solo como referencia): %s",
                length(operadores_agregado), paste(operadores_agregado, collapse = ", ")))
message("Nota: los agregados de mercado (Max/Avg/...) se calculan igual que los")
message("operadores reales (para tenerlos como referencia), pero se EXCLUYEN de")
message("las comparaciones 'entre operadores' de la Fase 4, porque no representan")
message("el precio de una casa específica sino el mejor/promedio precio del mercado.")

# ---- 1. Conversión a probabilidades brutas -----------------------
# p_bruta = 1 / cuota, para cada resultado (H, D, A) y cada operador.
for (op in operadores) {
  colH <- paste0(op, "H"); colD <- paste0(op, "D"); colA <- paste0(op, "A")
  base[, (paste0("pbruta_", op, "_H")) := 1 / get(colH)]
  base[, (paste0("pbruta_", op, "_D")) := 1 / get(colD)]
  base[, (paste0("pbruta_", op, "_A")) := 1 / get(colA)]
  # Margen (overround): exceso de la suma de probabilidades brutas sobre 1,
  # expresado en puntos porcentuales.
  base[, (paste0("margen_", op)) := 100 * (
    get(paste0("pbruta_", op, "_H")) +
      get(paste0("pbruta_", op, "_D")) +
      get(paste0("pbruta_", op, "_A")) - 1
  )]
}

# ---- 2. Métodos de remoción del margen ---------------------------
# Método 1: Normalización multiplicativa (proporcional)
# Reparte el margen proporcionalmente al tamaño de cada probabilidad.
# p_norm_i = p_bruta_i / sum(p_bruta)
normalizar_multiplicativo <- function(pH, pD, pA) {
  s <- pH + pD + pA
  list(H = pH / s, D = pD / s, A = pA / s)
}

# Método 2: Normalización aditiva
# Reparte el exceso (margen) en partes iguales entre los 3 resultados.
# p_norm_i = p_bruta_i - (sum(p_bruta) - 1) / 3
# Nota: puede producir probabilidades negativas en mercados muy
# desbalanceados (se recorta a 0 y se advierte si ocurre).
normalizar_aditivo <- function(pH, pD, pA) {
  exceso <- (pH + pD + pA - 1) / 3
  list(H = pH - exceso, D = pD - exceso, A = pA - exceso)
}

# Método 3 (bonificable): Método de Shin
# Resuelve numéricamente el parámetro z (proporción de "apostadores
# informados") tal que las probabilidades ajustadas sean consistentes.
# Referencia: Shin (1993), "Measuring the Incidence of Insider Trading
# in a Market for State-Contingent Claims".
normalizar_shin <- function(pH, pD, pA) {
  objetivo <- function(z) {
    num <- sqrt(z^2 + 4 * (1 - z) * pH^2 / (pH + pD + pA)) - z
    # Implementación simplificada de Shin para 3 resultados:
    # se resuelve z tal que sum(shin_i) = 1
    shin_i <- function(p, z) (sqrt(z^2 + 4 * (1 - z) * p^2 / sum(c(pH,pD,pA))) - z) / (2 * (1 - z))
    sum(shin_i(c(pH, pD, pA), z)) - 1
  }
  z_sol <- tryCatch(
    uniroot(objetivo, interval = c(1e-6, 0.5 - 1e-6))$root,
    error = function(e) NA_real_
  )
  if (is.na(z_sol)) return(list(H = NA_real_, D = NA_real_, A = NA_real_))
  shin_i <- function(p, z) (sqrt(z^2 + 4 * (1 - z) * p^2 / sum(c(pH,pD,pA))) - z) / (2 * (1 - z))
  list(H = shin_i(pH, z_sol), D = shin_i(pD, z_sol), A = shin_i(pA, z_sol))
}

# Aplica los métodos a un operador y agrega las columnas resultantes
aplicar_metodos <- function(dt, op) {
  colH <- paste0("pbruta_", op, "_H")
  colD <- paste0("pbruta_", op, "_D")
  colA <- paste0("pbruta_", op, "_A")
  
  res_mult <- dt[, normalizar_multiplicativo(get(colH), get(colD), get(colA))]
  dt[, (paste0("pnorm_mult_", op, "_H")) := res_mult$H]
  dt[, (paste0("pnorm_mult_", op, "_D")) := res_mult$D]
  dt[, (paste0("pnorm_mult_", op, "_A")) := res_mult$A]
  
  res_adit <- dt[, normalizar_aditivo(get(colH), get(colD), get(colA))]
  dt[, (paste0("pnorm_adit_", op, "_H")) := pmax(res_adit$H, 0)]
  dt[, (paste0("pnorm_adit_", op, "_D")) := pmax(res_adit$D, 0)]
  dt[, (paste0("pnorm_adit_", op, "_A")) := pmax(res_adit$A, 0)]
  
  n_negativas <- sum(res_adit$H < 0 | res_adit$D < 0 | res_adit$A < 0, na.rm = TRUE)
  if (n_negativas > 0) {
    message(sprintf("  [%s] Normalización aditiva: %d filas con probabilidad negativa (recortadas a 0)",
                    op, n_negativas))
  }
  
  dt
}

for (op in operadores) {
  message(sprintf("Aplicando métodos de remoción del margen para %s...", op))
  base <- aplicar_metodos(base, op)
}

# Shin es más costoso computacionalmente (resuelve una ecuación por
# fila): se aplica solo a un operador como demostración y para la
# bonificación (preferimos un operador REAL, no un agregado de
# mercado, y priorizamos B365 si está disponible por su cobertura
# histórica casi completa). Si quieres aplicarlo a todos los
# operadores, repite este bloque cambiando `operador_shin`.
operador_shin <- if ("B365" %in% operadores_reales) {
  "B365"
} else if (length(operadores_reales) > 0) {
  operadores_reales[1]
} else {
  operadores[1]  # fallback: solo si no se detectó ningún operador real
}
message(sprintf("Aplicando método de Shin (bonificable) para %s (puede tardar unos segundos)...",
                operador_shin))

colH <- paste0("pbruta_", operador_shin, "_H")
colD <- paste0("pbruta_", operador_shin, "_D")
colA <- paste0("pbruta_", operador_shin, "_A")

resultado_shin <- base[, {
  r <- normalizar_shin(get(colH), get(colD), get(colA))
  .(shin_H = r$H, shin_D = r$D, shin_A = r$A)
}, by = seq_len(nrow(base))]

base[, (paste0("pnorm_shin_", operador_shin, "_H")) := resultado_shin$shin_H]
base[, (paste0("pnorm_shin_", operador_shin, "_D")) := resultado_shin$shin_D]
base[, (paste0("pnorm_shin_", operador_shin, "_A")) := resultado_shin$shin_A]

# ---- 3. Distribución del margen (resultado con valor propio) -----
distribucion_margen <- rbindlist(lapply(operadores, function(op) {
  base[, .(
    Operador = op,
    Margen_medio_pct = mean(get(paste0("margen_", op)), na.rm = TRUE),
    Margen_mediana_pct = median(get(paste0("margen_", op)), na.rm = TRUE),
    Margen_sd_pct = sd(get(paste0("margen_", op)), na.rm = TRUE),
    Margen_min_pct = min(get(paste0("margen_", op)), na.rm = TRUE),
    Margen_max_pct = max(get(paste0("margen_", op)), na.rm = TRUE),
    N_partidos = sum(!is.na(get(paste0("margen_", op))))
  ), by = .(Liga, Temporada)]
}))

message("\n---- Distribución del margen por operador/liga/temporada ----")
print(distribucion_margen)

# ---- 4. Análisis de sensibilidad entre métodos --------------------
# Compara, para cada partido, la probabilidad normalizada del
# resultado H entre el método multiplicativo y el aditivo, y mide
# la diferencia absoluta media (en puntos porcentuales). Si esta
# diferencia es grande, las conclusiones podrían depender del
# método elegido - hay que reportarlo explícitamente.
sensibilidad <- rbindlist(lapply(operadores, function(op) {
  colmult <- paste0("pnorm_mult_", op, "_H")
  coladit <- paste0("pnorm_adit_", op, "_H")
  diff_abs <- abs(base[[colmult]] - base[[coladit]]) * 100
  data.table(
    Operador = op,
    Dif_media_pp = mean(diff_abs, na.rm = TRUE),
    Dif_max_pp = max(diff_abs, na.rm = TRUE),
    Dif_p95_pp = quantile(diff_abs, 0.95, na.rm = TRUE)
  )
}))

message("\n---- Sensibilidad: diferencia entre método multiplicativo y aditivo (prob. de H) ----")
print(sensibilidad)
message("\nInterpretación: si Dif_media_pp es pequeña (< 1 punto porcentual),")
message("los dos métodos dan resultados muy similares y las conclusiones no")
message("dependen del método. Si es grande, hay que reportarlo como limitación")
message("y decidir con cuál método te quedas (o reportar ambos).")

# ---- 5. Guardar salidas -------------------------------------------
# Se agrega la columna Tipo (Casa real / Agregado de mercado) para
# que quede documentado en los CSV cuáles operadores son comparables
# entre sí (Fase 4) y cuáles son solo referencia agregada.
distribucion_margen[, Tipo := fifelse(Operador %in% operadores_agregado,
                                      "Agregado de mercado", "Casa real")]
sensibilidad[, Tipo := fifelse(Operador %in% operadores_agregado,
                               "Agregado de mercado", "Casa real")]

fwrite(base, file.path(DIR_OUT, "base_con_probabilidades.csv"))
fwrite(distribucion_margen, file.path(DIR_OUT, "distribucion_margen.csv"))
fwrite(sensibilidad, file.path(DIR_OUT, "sensibilidad_metodos.csv"))

message("\nListo. Archivos guardados en data/processed/:")
message(" - base_con_probabilidades.csv (probabilidades brutas y normalizadas)")
message(" - distribucion_margen.csv")
message(" - sensibilidad_metodos.csv")

# ---- 6. Resumen final (para copiar y revisar de un vistazo) -----
# Con muchos operadores detectados, la salida cruda (por
# operador x liga x temporada) es larga para leer en consola.
# Este resumen agrega todo a nivel de operador para dar un
# vistazo rápido; el detalle completo queda en los CSV guardados.
mostrar_resumen_fase2 <- function() {
  agregado_margen <- distribucion_margen[, .(
    Margen_medio_pct = round(mean(Margen_medio_pct, na.rm = TRUE), 2),
    N_partidos_total = sum(N_partidos)
  ), by = Operador]
  agregado_margen[, Tipo := fifelse(Operador %in% operadores_agregado,
                                    "Agregado de mercado", "Casa real")]
  
  margen_reales    <- agregado_margen[Tipo == "Casa real"]
  margen_agregados <- agregado_margen[Tipo == "Agregado de mercado"]
  setorder(margen_reales, Margen_medio_pct)
  setorder(margen_agregados, Margen_medio_pct)
  
  agregado_sens <- sensibilidad[, .(Operador, Dif_media_pp = round(Dif_media_pp, 3))]
  agregado_sens[, Tipo := fifelse(Operador %in% operadores_agregado,
                                  "Agregado de mercado", "Casa real")]
  
  cat("\n")
  cat("================ RESUMEN FASE 2 ================\n")
  cat(sprintf("Operadores procesados:            %d (%d casas reales + %d agregados de mercado)\n",
              length(operadores), length(operadores_reales), length(operadores_agregado)))
  cat(sprintf("Métodos de remoción aplicados:     2 obligatorios (multiplicativo, aditivo)\n"))
  cat(sprintf("                                    + 1 bonificable (Shin, solo en %s)\n", operador_shin))
  cat("--------------------------------------------------\n")
  cat("MARGEN - solo casas de apuestas reales (lo que reporta el proyecto):\n")
  cat(sprintf("  Margen medio across casas reales: %.2f%%\n", mean(margen_reales$Margen_medio_pct)))
  cat(sprintf("  Casa con MENOR margen medio: %s (%.2f%%)\n",
              margen_reales$Operador[1], margen_reales$Margen_medio_pct[1]))
  cat(sprintf("  Casa con MAYOR margen medio: %s (%.2f%%)\n",
              margen_reales$Operador[nrow(margen_reales)],
              margen_reales$Margen_medio_pct[nrow(margen_reales)]))
  cat("\n  Todas las casas reales (ordenadas por margen):\n")
  print(margen_reales[, .(Operador, Margen_medio_pct, N_partidos_total)])
  cat("\nMARGEN - agregados de mercado (solo como referencia, NO se comparan como operador):\n")
  print(margen_agregados[, .(Operador, Margen_medio_pct, N_partidos_total)])
  cat("--------------------------------------------------\n")
  cat("Sensibilidad (diferencia multiplicativo vs. aditivo, prob. de H) - casas reales:\n")
  sens_reales <- agregado_sens[Tipo == "Casa real"]
  cat(sprintf("  Diferencia media across casas reales: %.3f puntos porcentuales\n",
              mean(sens_reales$Dif_media_pp, na.rm = TRUE)))
  if (mean(sens_reales$Dif_media_pp, na.rm = TRUE) < 1) {
    cat("  -> Diferencia pequeña: los métodos son consistentes entre sí.\n")
  } else {
    cat("  -> Diferencia notable: reportar ambos métodos y documentar como limitación.\n")
  }
  cat("====================================================\n")
  cat("Detalle completo por operador/liga/temporada disponible en:\n")
  cat("  data/processed/distribucion_margen.csv (columna 'Operador' - filtra por\n")
  cat("  los nombres de la lista de casas reales arriba para excluir agregados)\n")
  cat("  data/processed/sensibilidad_metodos.csv\n")
}

mostrar_resumen_fase2()
