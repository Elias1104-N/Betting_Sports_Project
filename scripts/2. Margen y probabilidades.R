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
  if (is.na(pH) || is.na(pD) || is.na(pA) || (pH <= 0) || (pD <= 0) || (pA <= 0)) {
    return(list(H = NA_real_, D = NA_real_, A = NA_real_, z = NA_real_))
  }
  s <- pH + pD + pA
  objetivo <- function(z) {
    shin_i <- function(p) (sqrt(z^2 + 4 * (1 - z) * (p^2) / s) - z) / (2 * (1 - z))
    shin_i(pH) + shin_i(pD) + shin_i(pA) - 1
  }
  z_res <- tryCatch(
    uniroot(objetivo, interval = c(1e-6, 0.5 - 1e-6)),
    error = function(e) NULL
  )
  if (is.null(z_res)) return(list(H = NA_real_, D = NA_real_, A = NA_real_, z = NA_real_))
  z_sol <- z_res$root
  shin_i <- function(p) (sqrt(z_sol^2 + 4 * (1 - z_sol) * (p^2) / s) - z_sol) / (2 * (1 - z_sol))
  list(H = shin_i(pH), D = shin_i(pD), A = shin_i(pA), z = z_sol)
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

# Shin es más exigente computacionalmente al resolver numéricamente z
# para cada partido. Se aplica a todos los OPERADORES_PRINCIPALES
# (B365, PS, PSC, WH) para permitir el análisis de sensibilidad completo
# y obtener la bonificación de +3 puntos (Criterio C).

operadores_shin <- intersect(OPERADORES_PRINCIPALES, operadores)

for (op_s in operadores_shin) {
  message(sprintf("Aplicando método de Shin para %s...", op_s))
  colH <- paste0("pbruta_", op_s, "_H")
  colD <- paste0("pbruta_", op_s, "_D")
  colA <- paste0("pbruta_", op_s, "_A")
  
  res_s <- mapply(normalizar_shin, base[[colH]], base[[colD]], base[[colA]], SIMPLIFY = FALSE)
  
  base[, (paste0("pnorm_shin_", op_s, "_H")) := vapply(res_s, function(x) x$H, numeric(1))]
  base[, (paste0("pnorm_shin_", op_s, "_D")) := vapply(res_s, function(x) x$D, numeric(1))]
  base[, (paste0("pnorm_shin_", op_s, "_A")) := vapply(res_s, function(x) x$A, numeric(1))]
  base[, (paste0("z_shin_", op_s)) := vapply(res_s, function(x) x$z, numeric(1))]
}

# ---- 3. Distribución del margen (resultado con valor propio) -----

distribucion_margen <- rbindlist(lapply(operadores, function(op) {
  col_z <- paste0("z_shin_", op)
  tiene_z <- col_z %in% names(base)
  
  base[, .(
    Operador = op,
    Margen_medio_pct = mean(get(paste0("margen_", op)), na.rm = TRUE),
    Margen_mediana_pct = median(get(paste0("margen_", op)), na.rm = TRUE),
    Margen_sd_pct = sd(get(paste0("margen_", op)), na.rm = TRUE),
    Margen_min_pct = min(get(paste0("margen_", op)), na.rm = TRUE),
    Margen_max_pct = max(get(paste0("margen_", op)), na.rm = TRUE),
    Z_shin_medio = if (tiene_z) mean(get(col_z), na.rm = TRUE) else NA_real_,
    N_partidos = sum(!is.na(get(paste0("margen_", op))))
  ), by = .(Liga, Temporada)]
}))

message("\n---- Distribución del margen por operador/liga/temporada ----")
print(distribucion_margen)

# ---- 4. Análisis de sensibilidad entre métodos --------------------
# Compara, para cada partido, la probabilidad normalizada del
# resultado H entre los distintos métodos:
# 1) Multiplicativo vs. Aditivo
# 2) Multiplicativo vs. Shin (donde esté disponible)
# 3) Aditivo vs. Shin

sensibilidad <- rbindlist(lapply(operadores, function(op) {
  colmult <- paste0("pnorm_mult_", op, "_H")
  coladit <- paste0("pnorm_adit_", op, "_H")
  colshin <- paste0("pnorm_shin_", op, "_H")
  
  diff_adit <- abs(base[[colmult]] - base[[coladit]]) * 100
  
  filas <- list(
    data.table(
      Operador = op,
      Comparacion = "Mult vs Adit",
      Dif_media_pp = mean(diff_adit, na.rm = TRUE),
      Dif_max_pp = max(diff_adit, na.rm = TRUE),
      Dif_p95_pp = quantile(diff_adit, 0.95, na.rm = TRUE)
    )
  )
  
  if (colshin %in% names(base)) {
    diff_shin_mult <- abs(base[[colmult]] - base[[colshin]]) * 100
    diff_shin_adit <- abs(base[[coladit]] - base[[colshin]]) * 100
    filas[[length(filas) + 1]] <- data.table(
      Operador = op,
      Comparacion = "Mult vs Shin",
      Dif_media_pp = mean(diff_shin_mult, na.rm = TRUE),
      Dif_max_pp = max(diff_shin_mult, na.rm = TRUE),
      Dif_p95_pp = quantile(diff_shin_mult, 0.95, na.rm = TRUE)
    )
    filas[[length(filas) + 1]] <- data.table(
      Operador = op,
      Comparacion = "Adit vs Shin",
      Dif_media_pp = mean(diff_shin_adit, na.rm = TRUE),
      Dif_max_pp = max(diff_shin_adit, na.rm = TRUE),
      Dif_p95_pp = quantile(diff_shin_adit, 0.95, na.rm = TRUE)
    )
  }
  rbindlist(filas)
}))

message("\n---- Sensibilidad entre métodos de remoción del margen (prob. de H) ----")
print(sensibilidad)

# ---- 5. Guardar salidas -------------------------------------------

distribucion_margen[, Tipo := fifelse(Operador %in% operadores_agregado,
                                      "Agregado de mercado", "Casa real")]
sensibilidad[, Tipo := fifelse(Operador %in% operadores_agregado,
                               "Agregado de mercado", "Casa real")]

fwrite(base, file.path(DIR_OUT, "base_con_probabilidades.csv"))
fwrite(distribucion_margen, file.path(DIR_OUT, "distribucion_margen.csv"))
fwrite(sensibilidad, file.path(DIR_OUT, "sensibilidad_metodos.csv"))

message("\nListo. Archivos guardados en outputs/:")
message(" - base_con_probabilidades.csv (probabilidades brutas y normalizadas)")
message(" - distribucion_margen.csv")
message(" - sensibilidad_metodos.csv")

# ---- 6. Resumen final (para copiar y revisar de un vistazo) -----

mostrar_resumen_fase2 <- function() {
  agregado_margen <- distribucion_margen[, .(
    Margen_medio_pct = round(mean(Margen_medio_pct, na.rm = TRUE), 2),
    Z_shin_medio = if (any(!is.na(Z_shin_medio))) round(mean(Z_shin_medio, na.rm = TRUE), 4) else NA_real_,
    N_partidos_total = sum(N_partidos)
  ), by = Operador]
  agregado_margen[, Tipo := fifelse(Operador %in% operadores_agregado,
                                    "Agregado de mercado", "Casa real")]
  
  margen_reales    <- agregado_margen[Tipo == "Casa real"]
  margen_agregados <- agregado_margen[Tipo == "Agregado de mercado"]
  setorder(margen_reales, Margen_medio_pct)
  setorder(margen_agregados, Margen_medio_pct)
  
  cat("\n")
  cat("================ RESUMEN FASE 2 ================\n")
  cat(sprintf("Operadores procesados:            %d (%d casas reales + %d agregados de mercado)\n",
              length(operadores), length(operadores_reales), length(operadores_agregado)))
  cat(sprintf("Métodos de remoción aplicados:     Multiplicativo, Aditivo\n"))
  cat(sprintf("                                    + Shin aplicado a: %s\n", paste(operadores_shin, collapse = ", ")))
  cat("--------------------------------------------------\n")
  cat("MARGEN Y PARÁMETRO SHIN (Z) - casas reales:\n")
  cat(sprintf("  Margen medio across casas reales: %.2f%%\n", mean(margen_reales$Margen_medio_pct)))
  cat("\n  Casas reales ordenadas por margen:\n")
  print(margen_reales[, .(Operador, Margen_medio_pct, Z_shin_medio, N_partidos_total)])
  cat("--------------------------------------------------\n")
  cat("Sensibilidad (diferencia de prob. de H en puntos porcentuales) - casas reales:\n")
  sens_reales <- sensibilidad[Tipo == "Casa real"]
  print(sens_reales[, .(Operador, Comparacion, Dif_media_pp = round(Dif_media_pp, 3), Dif_p95_pp = round(Dif_p95_pp, 3))])
  cat("====================================================\n")
}

mostrar_resumen_fase2()