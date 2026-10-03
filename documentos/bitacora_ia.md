# Bitácora de uso de Inteligencia Artificial

**Proyecto:** Proyecto 2 — ¿Están bien calibradas las casas de apuestas? Evaluación de pronósticos probabilísticos con datos históricos de cuotas (Premier League y La Liga, 2012/13–2019/20)  
**Curso:** Estadística Industrial · Ingeniería Industrial · Universidad del Magdalena · 2026-II  
**Entregable 4:** `bitacora_ia.md` (Carpeta principal del proyecto)  
**Herramientas utilizadas:** Claude (Anthropic) y Antigravity (Google DeepMind)  
**Periodo cubierto:** 8 de septiembre – 29 de septiembre de 2026  
**Integrantes:** Elías Parra - María Mónica Murillo  
**Docente:** Enrique J. De La Hoz Domínguez  

---

## Nota metodológica

Esta bitácora registra cada interacción relevante con IA durante el desarrollo del pipeline (`config.R`, `scripts/0.Renombre...` a `5. comparación ligas.R`, `run_all.R` y `reporte_calibracion.Rmd`). Se documenta con qué criterio se usó la IA: qué se le preguntó, qué respondió, cómo se verificó esa respuesta contra el dato real o contra la lógica estadística del proyecto, y si se aceptó, se corrigió o se descartó. 

Para este proyecto usamos la inteligencia artificial como un asistente de apoyo en programación en R, pero validando siempre lo que nos arrojaba y sugería. La IA suele cometer errores conceptuales graves en estadística (inventa hipótesis, confunde muestras independientes con datos apareados o mete sesgos en las pruebas), así que nos propusimos auditar cada línea de código, cada fórmula y cada interpretación que nos daba.

El equipo es responsable de todo lo entregado — la IA propuso enfoques y código; la verificación, la auditoría matemática y la decisión final fueron del equipo en cada caso.

---

### 1. Martes 8 de septiembre — Planeación general y correspondencia con la rúbrica
* **Objetivo:** Definir la hoja de ruta metodológica en RStudio para evaluar pronósticos probabilísticos asegurando el cumplimiento de todos los entregables.
* **Prompt:** “Queremos evaluar si las cuotas de fútbol están bien calibradas comparando varias casas de apuestas en Premier League y La Liga. ¿Cómo estructuramos el proyecto paso a paso en R para abordar la limpieza, márgenes y pruebas de calibración?”
* **Respuesta obtenida:** Propuso un esquema básico en 5 pasos (carga de datos, normalización de probabilidades simple, cálculo de Brier score, regresión logística estándar y automatización).
* **Verificación aplicada:** Contrastamos la propuesta con la guía del proyecto (`Proyecto2_Apuestas.html`). Detectamos que la IA omitía los requerimientos metodológicos más pesados: no incluía la descomposición multiclase de Murphy (+2 pts), ignoraba el Ranked Probability Score (RPS) para variables ordenadas (+2 pts), y asumía independencia entre casas ignorando que cotizan los mismos partidos. Le exigimos reestructurar el flujo en 6 fases formales incorporando estos contrastes.
* **Resultado:** Aceptado con modificaciones.

---

### 2. Miércoles 9 de septiembre — Definición del alcance y balance muestral (config.R)
* **Objetivo:** Delimitar las temporadas y ligas a evaluar, calculando el tamaño muestral teórico de balance.
* **Prompt:** “Vamos a trabajar con la Premier League (E0) y La Liga (SP1) desde 2012 hasta 2020. ¿Cuántas temporadas y partidos representan en total para fijarlo en un archivo de configuración central?”
* **Respuesta obtenida:** Tradujo el rango a 8 temporadas completas (2012/13 a 2019/20) para 2 ligas (16 combinaciones liga-temporada) y estimó un volumen teórico de exactamente 6.080 partidos ($16 \times 380$).
* **Verificación aplicada:** Confirmamos en el calendario oficial que, a pesar de la suspensión temporal por COVID-19 en 2020, ambas ligas completaron sus 380 partidos a puerta cerrada. Definimos los parámetros centrales en `config.R` y fijamos 6.080 partidos como nuestra meta de balance para la limpieza.
* **Resultado:** Aceptado.

---

### 3. Viernes 11 de septiembre — Fase 0 y 1: alcance y problema de descarga (config.R)
* **Objetivo:** Definir la estructura de ingesta de datos para las 8 temporadas de Premier League y La Liga (2012/13 a 2019/20) y resolver los fallos de descarga directa desde R.
* **Prompt:** “Queremos descargar automáticamente desde football-data.co.uk los CSVs de Premier League y La Liga de 2012 a 2020 con un script en R usando httr. ¿Cómo hacemos la función para que baje los 16 archivos?”
* **Respuesta obtenida:** Propuso una función con bucle `GET()` forzando IPv4 y reintentos para descargar los 16 archivos directamente a una carpeta temporal.
* **Verificación aplicada:** Al ejecutar la función arrojó `Failed to connect to www.football-data.co.uk port 443: Timeout was reached`. Probamos abrir la URL en el navegador de la universidad y tampoco cargaba (`ERR_CONNECTION_TIMED_OUT`). Confirmamos que la red institucional tenía bloqueado el dominio. Para no dejar un pipeline frágil que fallara, entramos en otro horario, descargamos los 16 CSVs a mano a `data/raw/` y le pedimos a la IA reorientar el código para trabajar sobre archivos locales.
* **Resultado:** Aceptado con modificaciones.

---

### 4. Sábado 12 de septiembre — Fase 0: renombrado automático de archivos (0.Renombre de las bases de datos.R)
* **Objetivo:** Normalizar de forma determinística los nombres de los 16 archivos CSV descargados manualmente.
* **Prompt:** “Los archivos descargados tienen nombres heterogéneos como E0 (1).csv o SP1_2012.csv. Necesito una función que lea el interior de los CSVs en data/raw/, identifique la liga y la temporada por las columnas Div y Date, y los renombre in situ a {liga}_{temporada}.csv.”
* **Respuesta obtenida:** Generó el script `0.Renombre de las bases de datos.R`, que lee los encabezados con `fread(..., nrows = 400)`, extrae la liga de `Div` e infiere la temporada tomando agosto como mes de corte, renombrando los archivos directamente en `data/raw/`.
* **Verificación aplicada:** Se ejecutó en local y se comprobó en el explorador de archivos que los 16 CSVs quedaron exactamente nombrados de `E0_1213.csv` a `SP1_1920.csv`, sin duplicados ni pérdidas.
* **Resultado:** Aceptado.

---

### 5. Lunes 14 de septiembre — Fase 1: limpieza y validación de 6.080 partidos (1. Limpieza de datos.R)
* **Objetivo:** Consolidar los 16 torneos verificando marcadores, fechas y cuotas, auditando cualquier descarte.
* **Prompt:** “Al correr la consolidación de los 16 archivos me salen 6.081 filas y el script descarta 1 fila. Quiero una función de resumen y un CSV que me diga exactamente qué fila se descartó y por qué, para verificar que no estoy botando un partido real.”
* **Respuesta obtenida:** Creó `mostrar_resumen_fase1()` y la exportación de `filas_descartadas_justificacion.csv` con la columna explicativa `Motivo`.
* **Verificación aplicada:** Auditamos la fila excluida: era un registro totalmente en blanco de la Premier League 2014/15 sin fecha ni equipos. Al descartarla, la base quedó con exactamente **6.080 partidos limpios**, cuadrando al 100% con el fixture teórico esperado.
* **Resultado:** Aceptado.

---

### 6. Martes 15 de septiembre — Fase 1: guarda temporal de Pinnacle (config.R)
* **Objetivo:** Proteger el código contra la advertencia pública de Football-Data sobre inconsistencias en cuotas de Pinnacle posteriores al 23 de julio de 2025.
* **Prompt:** “Football-Data tiene un aviso que dice que las cuotas de Pinnacle después del 23 de julio de 2025 no son confiables. Como nuestros datos son de 2012 a 2020, ¿es necesario hacer algo o lo dejamos pasar?”
* **Respuesta obtenida:** Sugirió inicialmente ignorar la advertencia porque nuestra muestra histórica terminaba en 2020.
* **Verificación aplicada:** Rechazamos ignorarlo. Si en el futuro se incorporan temporadas nuevas, el código tragaría datos corruptos en silencio. Le exigimos definir en `config.R` la constante `PINNACLE_FECHA_CORTE <- as.Date("2025-07-23")` y anular automáticamente (`NA`) las cuotas de Pinnacle desde esa fecha. Confirmamos que en nuestra muestra anuló 0 cuotas, pero el pipeline quedó protegido.
* **Resultado:** Corregido por el equipo.

---

### 7. Jueves 17 de septiembre — Fase 2: error conceptual de márgenes negativos (2. Margen y probabilidades.R)
* **Objetivo:** Calcular el margen del operador ($c = \sum 1/o_i - 1$) y detectar inconsistencias en los operadores.
* **Prompt:** “Calculé el margen medio sobre todas las columnas de cuotas y me salen operadores con margen negativo: MaxC (-0.87%), BbMx (-0.21%) y Max (0.22%). ¿Por qué una casa de apuestas daría margen negativo?”
* **Respuesta obtenida:** Explicó que correspondían a cuotas de arbitraje y propuso simplemente filtrar los valores negativos con `c > 0`.
* **Verificación aplicada:** Rechazamos ese parche. Al estudiar la documentación de Football-Data, descubrimos que `Max`, `Avg`, `BbMx` y `BbAv` no son casas de apuestas reales, sino **agregados de mercado** (la cuota máxima o promedio entre varias casas). Mezclar las cuotas máximas genera cuotas sintéticas de arbitraje con margen negativo. Obligamos a clasificar los operadores en 16 casas reales y 6 agregados. Al recalcularlo, todas las casas reales arrojaron márgenes positivos lógicos (2.24% a 6.96%).
* **Resultado:** Corregido por el equipo.

---

### 8. Viernes 18 de septiembre — Fase 2: normalización aditiva y probabilidades negativas (2. Margen y probabilidades.R)
* **Objetivo:** Remover el margen con el método aditivo ($p_i = 1/o_i - c/3$) preservando la coherencia probabilística.
* **Prompt:** “Al aplicar el método aditivo en William Hill, una probabilidad visitante dio negativa porque la cuota era muy alta. La IA me sugirió truncar a cero con pmax(0, p). ¿Eso está bien?”
* **Respuesta obtenida:** Sugirió truncar a 0 con `pmax(0, p)` para evitar errores en las operaciones siguientes.
* **Verificación aplicada:** Rechazamos truncar a cero: si una probabilidad se fuerza a 0 sin reescalar las otras dos, **la suma ya no da 1**, violando los axiomas de Kolmogorov. Exigimos que si un partido arroja una probabilidad aditiva negativa (ocurrió en exactamente 1 fila de William Hill), las 3 probabilidades del partido se anulen como `NA` y se registren en `aditivo_filas_anuladas.csv`.
* **Resultado:** Descartado y corregido por el equipo.

---

### 9. Sábado 19 de septiembre — Fase 2: modelo de Shin (1993) y convergencia de insiders z (2. Margen y probabilidades.R)
* **Objetivo:** Implementar la deducción de probabilidades bajo asimetría de información resolviendo numéricamente la proporción de insiders $z$.
* **Prompt:** “Necesitamos programar el método de Shin (1993) para calcular z y las probabilidades normalizadas en R. ¿Cómo formulamos la ecuación que resuelve uniroot?”
* **Respuesta obtenida:** Implementó la búsqueda de raíces sobre $\sum \pi_i(z) - 1 = 0$ con `uniroot()`.
* **Verificación aplicada:** Advertimos que si `uniroot()` no converge en cuotas extremas, devuelve `NA` y puede propagar valores faltantes. Auditamos la convergencia generando `outputs/shin_no_convergencia.csv`, comprobando que en los 6.074 partidos de la muestra común hubo **0 fallos de convergencia**. Además, $z$ resultó menor en Pinnacle ($z \approx 0.0113$) que en William Hill ($z \approx 0.0290$), coherente con el perfil de bajo margen y altos límites de Pinnacle.
* **Resultado:** Aceptado con verificación.

---

### 10. Lunes 21 de septiembre — Fase 3: muestra común apareada (3. Evaluación de calibración.R)
* **Objetivo:** Garantizar que la comparación entre operadores principales se realice bajo condiciones de mercado idénticas.
* **Prompt:** “Para comparar el Brier Score entre Bet365, Pinnacle y William Hill, ¿usamos todos los partidos que tiene cada una o filtramos?”
* **Respuesta obtenida:** Inicialmente propuso calcular el Brier de cada operador sobre todos sus partidos disponibles por separado ($N = 6.080$ para Bet365, $N = 6.075$ para PS).
* **Verificación aplicada:** Rechazamos evaluar conjuntos de partidos distintos porque introduce sesgos de selección muestral. Impusimos un filtro estricto de **muestra común apareada** con **6.074 partidos** donde los 4 operadores principales tienen cuotas completas simultáneamente, requisito indispensable para las pruebas apareadas posteriores.
* **Resultado:** Corregido por el equipo.

---

### 11. Martes 22 de septiembre — Fase 3: trampa de dependencia en Hosmer-Lemeshow (3. Evaluación de calibración.R)
* **Objetivo:** Evaluar la bondad de ajuste de calibración respetando el supuesto de independencia del estadístico chi-cuadrado.
* **Prompt:** “Genera la función de Hosmer-Lemeshow para evaluar la calibración de las cuotas de cada operador con 10 intervalos.”
* **Respuesta obtenida:** Entregó una función que apilaba todas las filas en formato largo ($6.074 \times 3 = 18.222$ observaciones) y corría un único test chi-cuadrado por operador.
* **Verificación aplicada:** Identificamos una violación metodológica grave: en un mismo partido, las opciones $H, D, A$ están ligadas por $\sum p = 1$ y $\sum o = 1$. Juntarlas en la misma prueba viola la independencia de observaciones del test chi-cuadrado. Obligamos a reescribir la función evaluando la prueba **de forma independiente para cada resultado ($H$, $D$, $A$)**, generando 12 pruebas separadas (4 operadores $\times$ 3 resultados), donde cada partido aporta una única observación binaria independiente.
* **Resultado:** Descartado y corregido por el equipo.

---

### 12. Miércoles 23 de septiembre — Fase 3: justificación de grados de libertad en Hosmer-Lemeshow
* **Objetivo:** Definir si los grados de libertad del test debían ser $gl = G-2$, $G-1$ o $G$.
* **Prompt:** “En Hosmer-Lemeshow clásico se usa gl = G - 2, pero aquí no estamos ajustando una regresión logística sino evaluando probabilidades exógenas del mercado. ¿Qué gl corresponde usar?”
* **Respuesta obtenida:** Sugirió cambiar a $gl = G - 1$ argumentando que no se estiman parámetros sobre la muestra, manteniendo una postura dogmática sobre esta regla.
* **Verificación aplicada:** Revisamos la literatura econométrica. La resta de 2 parámetros proviene del intercepto y pendiente de un modelo logístico ajustado por máxima verosimilitud en la muestra; con probabilidades exógenas de mercado, teóricamente corresponde $gl = G$ (o $G-1$ por la restricción de suma total). Programamos la exportación de los valores p bajo los tres criterios ($G$, $G-1$, $G-2$) en `hosmer_lemeshow.csv`, demostrando en el informe que las conclusiones prácticas no dependen de esa elección.
* **Resultado:** Aceptado con ampliación crítica.

---

### 13. Jueves 24 de septiembre — Fase 3: Murphy multiclase y término intra-intervalo (3. Evaluación de calibración.R)
* **Objetivo:** Descomponer el Brier Score en Fiabilidad, Resolución e Incertidumbre (+2 pts bonificación).
* **Prompt:** “¿Cómo se programa la descomposición de Murphy para el Brier multiclase 1X2 y cómo se verifica la identidad matemática Brier = Fiabilidad - Resolución + Incertidumbre?”
* **Respuesta obtenida:** Entregó la formulación matemática y el código para calcular los tres términos por operador.
* **Verificación aplicada:** Al sumar los componentes vimos una discrepancia de $\approx 0.002$ respecto al Brier real. Auditamos la matemática y descubrimos que al discretizar probabilidades continuas en bines de ancho 0.10, surge un **término intra-intervalo** (entre $-0.0017$ y $-0.0022$). Anotamos esta salvedad técnica en el reporte para justificar por qué las comparaciones entre casas se hacen con el Brier real, usando Murphy exclusivamente para aislar la Fiabilidad (descalibración pura $\le 0.0014$, $< 0.25\%$ del error total).
* **Resultado:** Aceptado con justificación teórica.

---

### 14. Viernes 25 de septiembre — Fase 3: inferencia apareada: Friedman y Wilcoxon con Holm (3. Evaluación de calibración.R)
* **Objetivo:** Contrastar formalmente las diferencias de calidad probabilística entre operadores.
* **Prompt:** “¿Qué prueba estadística usamos para demostrar si Bet365, Pinnacle y William Hill son estadísticamente distintas en Brier Score?”
* **Respuesta obtenida:** Sugirió inicialmente un ANOVA de una vía o pruebas t para muestras independientes.
* **Verificación aplicada:** Rechazamos el supuesto de muestras independientes. Las cuotas son medidas repetidas sobre los mismos 6.074 partidos. Exigimos la prueba no paramétrica global de **Friedman** ($\chi^2 = 253.54, p = 8.79 \times 10^{-56}$) y pruebas apareadas post-hoc de **Wilcoxon con corrección de Holm** para comparaciones múltiples, demostrando que Pinnacle supera significativamente a las casas recreacionales.
* **Resultado:** Corregido por el equipo.

---

### 15. Sábado 26 de septiembre — Fase 4: errores estándar por clúster en pendiente logística beta (4. Desviaciones sistemáticas.R)
* **Objetivo:** Evaluar el sesgo favorito-longshot mediante la pendiente de calibración logística $\text{logit}(P) = \alpha + \beta \cdot \text{logit}(p)$.
* **Prompt:** “Ajusta la regresión logística para estimar la pendiente beta de calibración en Bet365, Pinnacle y William Hill.”
* **Respuesta obtenida:** Ajustó un modelo `glm()` convencional asumiendo filas independientes.
* **Verificación aplicada:** Advertimos que como cada partido aporta 3 filas ($H, D, A$), existe correlación intra-partido que subestima el error estándar de $\beta$. Exigimos calcular **errores estándar robustos por clúster de partido**. El error estándar subió de $0.022$ a $0.029$; como consecuencia directa, el sesgo de Bet365 bajo el método multiplicativo pasó de ser falsamente significativo ($p = 0.013$) a no significativo tras Holm ($p = 0.060$).
* **Resultado:** Corregido por el equipo.

---

### 16. Domingo 27 de septiembre — Fase 4: desagregación de beta y artefacto de los empates (4. Desviaciones sistemáticas.R)
* **Objetivo:** Explicar por qué la pendiente logística conjunta $\beta$ daba mayor a 1 en el método multiplicativo.
* **Prompt:** “La pendiente conjunta beta da 1.05 a 1.10. ¿Esto prueba que los apostadores sobreestiman las sorpresas en todos los mercados?”
* **Respuesta obtenida:** Respondió afirmativamente, atribuyéndolo al sesgo cognitivo tradicional de sobrestimación de probabilidades bajas.
* **Verificación aplicada:** El equipo sospechó del comportamiento particular del empate ($D$), cuyas probabilidades están comprimidas entre 20% y 35%. Obligamos a la IA a estimar $\beta$ **por separado para $H$, $D$ y $A$**. El hallazgo fue contundente: para $H$ y $A$, $\beta$ se mantuvo entre **$0.99$ y $1.07$** (calibración excelente), mientras que para el empate ($D$) se disparó a **$1.23 - 1.39$**. Demostramos que el sesgo conjunto aparente no proviene de las sorpresas en victorias locales o visitantes, sino del comportamiento matemático del empate.
* **Resultado:** Descartado y reformulado por el equipo.

---

### 17. Lunes 28 de septiembre — Fase 3 y 4: refutación empírica de ventaja local en COVID y remoción aleatoria
* **Objetivo:** Evaluar la sensibilidad del modelo al excluir los 200 partidos post-reanudación por COVID-19 en 2020.
* **Prompt:** “Al quitar los 200 partidos de COVID, William Hill en victoria local (WH-H) deja de rechazar Hosmer-Lemeshow. ¿A qué se debe este cambio?”
* **Respuesta obtenida (Hipótesis inventada por la IA):** Argumentó que la falta de público había alterado estructuralmente la ventaja de local, descalibrando las cuotas de William Hill durante la pandemia.
* **Verificación aplicada:** Auditamos las cuotas de esos 200 partidos a puerta cerrada y **desmentimos a la IA con los datos reales**: la victoria local observada fue del **$43.5\%$**, mientras que las casas pronosticaban entre **$41.8\%$ y $42.3\%$** (los locales ganaron más de lo predicho, desviación positiva $+1.2$ a $+1.6$ pp). La IA tuvo que **retirar su hipótesis textual en el chat**. Diseñamos además un experimento de control retirando 200 partidos al azar en 200 réplicas (`remocion_aleatoria_hl.csv`), confirmando que en el 47% de las veces el rechazo también desaparecía por simple inestabilidad muestral del chi-cuadrado.
* **Resultado:** Refutado y corregido por el equipo.

---

### 18. Martes 29 de septiembre — Fase 6 y orquestador: discrepancia Wilcoxon vs. Bootstrap y robustez en Windows (run_all.R)
* **Objetivo:** Verificar los contrastes apareados en el reporte HTML y resolver los fallos de consola y tildes en Windows.
* **Prompt:** “En el borrador del reporte dice que todas las casas son significativamente distintas entre sí. Además, en RStudio la consola se corta en la Fase 2 y en Windows fallan los scripts con tildes.”
* **Respuesta obtenida:** Afirmó que las diferencias eran significativas por el p-valor de Wilcoxon; explicó que la consola de RStudio tiene un búfer de 1.000 líneas y recomendó estandarizar nombres de archivo.
* **Verificación aplicada:** Al auditar la tabla, descubrimos que el **Intervalo Bootstrap por Bloques (liga-temporada-mes)** para la diferencia media de Brier entre Bet365 y William Hill es **$[-0.00138, +0.00003]$**, el cual **incluye el cero**. Corregimos el texto del `.Rmd`: aunque Wilcoxon rechaza igualdad de pseudomedianas, en media la diferencia no es concluyente. En `run_all.R` implementamos captura completa en `outputs/log_ejecucion.txt` y búsqueda de scripts por expresiones regulares (`ejecutar_script("3.*calibraci")`) con `encoding = "UTF-8"`. El pipeline corrió de corrido en **7.88 minutos** sin errores.
* **Resultado:** Corregido y validado por el equipo.

---

## Resumen de Interacciones

| # | Fecha | Etapa / Script | Tipo de Intervención | Resultado |
| :-: | :---: | :--- | :--- | :--- |
| **1** | 08 sep | `config.R` | Alcance inicial y contraste con la rúbrica | Aceptado con modificaciones |
| **2** | 09 sep | `config.R` | Definición de fixtures y balance de 6.080 partidos | Aceptado |
| **3** | 11 sep | `config.R` | Fallo de descarga y resolución local manual | Aceptado con modificaciones |
| **4** | 12 sep | `0.Renombre...` | Renombrado automático de archivos in situ | Aceptado |
| **5** | 14 sep | `1. Limpieza...` | Validación de 6.080 partidos y fila descartada | Aceptado |
| **6** | 15 sep | `config.R` | Guarda temporal de Pinnacle post-julio 2025 | Corregido por el equipo |
| **7** | 17 sep | `2. Margen...` | Corrección de márgenes negativos en agregados | Corregido por el equipo |
| **8** | 18 sep | `2. Margen...` | Prohibición de truncar probabilidades aditivas a cero | Descartado y corregido |
| **9** | 19 sep | `2. Margen...` | Modelo de Shin (1993) y convergencia de insiders $z$ | Aceptado con verificación |
| **10**| 21 sep | `3. Calibración...`| Construcción de muestra común apareada ($N=6.074$) | Corregido por el equipo |
| **11**| 22 sep | `3. Calibración...`| Independencia en Hosmer-Lemeshow (H, D, A separados) | Descartado y corregido |
| **12**| 23 sep | `3. Calibración...`| Discusión teórica de grados de libertad ($G, G-1, G-2$) | Aceptado con ampliación |
| **13**| 24 sep | `3. Calibración...`| Descomposición de Murphy y término intra-intervalo | Aceptado con justificación |
| **14**| 25 sep | `3. Calibración...`| Inferencia apareada: Friedman y Wilcoxon con Holm | Corregido por el equipo |
| **15**| 26 sep | `4. Desviaciones...`| Errores estándar por clúster en pendiente logística | Corregido por el equipo |
| **16**| 27 sep | `4. Desviaciones...`| Desagregación de $\beta$ y artefacto del empate | Descartado y reformulado |
| **17**| 28 sep | `3. Calibración...`| Refutación de la hipótesis de ventaja local en COVID | Refutado por el equipo |
| **18**| 29 sep | `run_all.R` | Bootstrap por bloques, log persistente y carga en Windows | Corregido y validado |

---

## 3. Conclusión luego de utilizar la IA

Para este proyecto usamos la inteligencia artificial como un asistente de apoyo en programación en R, pero validando siempre lo que nos arrojaba y sugería. La IA suele cometer errores conceptuales graves en estadística (inventa hipótesis, confunde muestras independientes con datos apareados o mete sesgos en las pruebas), así que nos propusimos auditar cada línea de código, cada fórmula y cada interpretación que nos daba.

En esta bitácora dejamos el registro real de las consultas más importantes que hicimos, lo que la IA nos propuso, las metidas de pata o limitaciones que le encontramos, y cómo nosotros mismos tuvimos que corregirla y guiarla para que el análisis fuera metodológicamente impecable y cumpliera con toda la rúbrica.

Trabajar con la IA en este proyecto fue muy útil para acelerar la escritura de código en R y estructurar visualmente las tablas, pero pudimos evidenciar que habían algunos errores técnicos que pasaba por alto y muchas veces decía que algo estaba bien y, después de volver a preguntar, revisaba más a detalle lo solicitado y comentaba errores que antes no reportaba. En varias ocasiones la IA:
* Sugirió métodos matemáticamente inválidos (truncar probabilidades a 0 rompiendo la suma a 1).
* Cometió violaciones de independencia estadística (juntar $H, D, A$ en Hosmer-Lemeshow).
* Se inventó narrativas sin base en los datos (la teoría de la ventaja de local en COVID).
* Exageró conclusiones estadísticas basándose únicamente en p-valores sin mirar los intervalos bootstrap ni la relevancia práctica.

Cada tabla, gráfica y número que aparece en el informe final fue revisado, cuestionado y validado directamente por nosotros en RStudio.
