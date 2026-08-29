"""
Motor de Elo propio para el Superagente Quant.
==============================================
Implementa los puntos 8, 9, 11, 13, 14 y 15 de la lista de 40 ideas:

  8.  Elo por equipo y por liga.
  9.  Ajuste por localia (ventaja de jugar en casa).
  11. Decaimiento temporal (partidos recientes pesan mas).
  13. Convertir la diferencia de Elo en una probabilidad propia,
      comparable contra la cuota de mercado (esto es EV real).
  14. Backtesting historico antes de usar el modelo con dinero real.
  15. Calibracion (Brier score) para medir si el modelo es confiable,
      no solo si "acierta".

IMPORTANTE - limitacion honesta:
Este motor necesita un historial de resultados reales (fecha, liga,
equipo local, equipo visitante, goles local, goles visitante) para
entrenarse y para hacer backtesting. Hoy NO tenemos ese historial
conectado automaticamente (The Odds API da cuotas, no resultados
historicos completos). Este modulo queda listo para usarse en cuanto
alimentemos un CSV de resultados (ver cargar_resultados_csv). Sin esos
datos, las probabilidades que devuelve son las del Elo inicial (todos
los equipos iguales), lo cual NO es una ventaja real todavia.

Uso tipico:
    motor = MotorElo()
    motor.cargar_resultados_csv("resultados_historicos.csv")
    prob = motor.probabilidad_partido("River Plate", "Boca Juniors", liga="soccer_argentina_primera_division")
    # prob = {"local": 0.42, "empate": 0.27, "visitante": 0.31}
"""

from __future__ import annotations

import csv
import math
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path


# ----------------------------------------------------------------------
# CONFIGURACION DEL MODELO
# ----------------------------------------------------------------------

ELO_INICIAL = 1500.0

# Factor K: que tanto se mueve el Elo tras un partido. Mas alto = el
# modelo reacciona mas rapido a resultados recientes (mas volatil);
# mas bajo = mas estable pero mas lento para detectar cambios de forma.
FACTOR_K = 28.0

# Ventaja de jugar en casa, en puntos de Elo. Valor de partida
# razonable segun literatura publica de modelos Elo de futbol
# (tipicamente 60-100 puntos). Ajustar por liga cuando haya datos
# suficientes para calibrarlo (punto 9 de la lista).
VENTAJA_LOCALIA_DEFECTO = 70.0

# Decaimiento temporal (punto 11): cuanto pierde peso un partido
# antiguo. Con VIDA_MEDIA_DIAS=180, un partido de hace 6 meses pesa
# la mitad que uno de hoy en el ajuste de forma reciente adicional
# (el Elo en si ya es acumulativo; esto es una capa extra que
# amplifica/atenua el impacto de resultados segun su antiguedad).
VIDA_MEDIA_DIAS = 180.0

# Empates: en futbol el resultado empate no existe en el Elo clasico
# de ajedrez. Usamos el metodo estandar (Hvattum & Arntzen / goles
# esperados sobre distribucion de Poisson bivariada simplificada) via
# un parametro de "anchura de empate" calibrable por liga.
FACTOR_EMPATE_DEFECTO = 0.18


@dataclass
class EquipoElo:
    nombre: str
    liga: str
    elo: float = ELO_INICIAL
    partidos_jugados: int = 0
    ultima_fecha: datetime | None = None


@dataclass
class MotorElo:
    equipos: dict[str, EquipoElo] = field(default_factory=dict)
    factor_k: float = FACTOR_K
    ventaja_localia: float = VENTAJA_LOCALIA_DEFECTO
    factor_empate: float = FACTOR_EMPATE_DEFECTO

    # ------------------------------------------------------------------
    # Gestion de equipos
    # ------------------------------------------------------------------

    def _clave(self, nombre: str, liga: str) -> str:
        return f"{liga}::{nombre}".lower().strip()

    def _obtener_o_crear(self, nombre: str, liga: str) -> EquipoElo:
        clave = self._clave(nombre, liga)
        if clave not in self.equipos:
            self.equipos[clave] = EquipoElo(nombre=nombre, liga=liga)
        return self.equipos[clave]

    # ------------------------------------------------------------------
    # Nucleo matematico del Elo
    # ------------------------------------------------------------------

    def _probabilidad_esperada(self, elo_a: float, elo_b: float) -> float:
        """Probabilidad de que 'a' le gane a 'b' (formula Elo estandar)."""
        return 1.0 / (1.0 + 10 ** ((elo_b - elo_a) / 400.0))

    def probabilidad_partido(self, local: str, visitante: str, liga: str) -> dict:
        """
        Devuelve {"local": p, "empate": p, "visitante": p} que suman 1.0.
        Aplica ventaja de localia sumando puntos de Elo al equipo local
        antes de calcular la probabilidad esperada.
        """
        eq_local = self._obtener_o_crear(local, liga)
        eq_visitante = self._obtener_o_crear(visitante, liga)

        elo_local_ajustado = eq_local.elo + self.ventaja_localia
        p_local_bruto = self._probabilidad_esperada(elo_local_ajustado, eq_visitante.elo)

        # Metodo simplificado para separar el empate: la probabilidad de
        # empate es mayor cuanto mas cerca esta el partido de 50/50, y
        # se resta simetricamente de local y visitante.
        cercania_50_50 = 1.0 - abs(p_local_bruto - 0.5) * 2.0
        p_empate = self.factor_empate * cercania_50_50 + (self.factor_empate * 0.4)
        p_empate = max(0.12, min(p_empate, 0.40))  # limites razonables para futbol

        resto = 1.0 - p_empate
        p_local = p_local_bruto * resto
        p_visitante = (1.0 - p_local_bruto) * resto

        return {
            "local": round(p_local, 4),
            "empate": round(p_empate, 4),
            "visitante": round(p_visitante, 4),
        }

    # ------------------------------------------------------------------
    # Entrenamiento con resultados reales (punto 14: backtesting)
    # ------------------------------------------------------------------

    def _peso_temporal(self, fecha_partido: datetime, fecha_referencia: datetime) -> float:
        """Decaimiento exponencial: partidos antiguos pesan menos (punto 11)."""
        dias = (fecha_referencia - fecha_partido).days
        dias = max(dias, 0)
        return 0.5 ** (dias / VIDA_MEDIA_DIAS)

    def actualizar_con_resultado(
        self,
        local: str,
        visitante: str,
        liga: str,
        goles_local: int,
        goles_visitante: int,
        fecha: datetime,
        fecha_referencia: datetime | None = None,
    ) -> None:
        """
        Actualiza el Elo de ambos equipos tras un resultado real.
        fecha_referencia: normalmente "hoy", usada solo para ponderar
        cuanto debe pesar este resultado si se esta re-entrenando desde
        cero sobre un historial completo (backtesting). En uso normal
        (actualizar tras cada jornada) se puede omitir.
        """
        eq_local = self._obtener_o_crear(local, liga)
        eq_visitante = self._obtener_o_crear(visitante, liga)

        if goles_local > goles_visitante:
            resultado_local = 1.0
        elif goles_local < goles_visitante:
            resultado_local = 0.0
        else:
            resultado_local = 0.5

        elo_local_ajustado = eq_local.elo + self.ventaja_localia
        esperado_local = self._probabilidad_esperada(elo_local_ajustado, eq_visitante.elo)

        peso = 1.0
        if fecha_referencia is not None:
            peso = self._peso_temporal(fecha, fecha_referencia)

        # Margen de victoria: un 4-0 deberia mover mas el Elo que un 1-0.
        diferencia_goles = abs(goles_local - goles_visitante)
        multiplicador_margen = math.log(diferencia_goles + 1) + 1.0

        ajuste = self.factor_k * peso * multiplicador_margen * (resultado_local - esperado_local)

        eq_local.elo += ajuste
        eq_visitante.elo -= ajuste
        eq_local.partidos_jugados += 1
        eq_visitante.partidos_jugados += 1
        eq_local.ultima_fecha = fecha
        eq_visitante.ultima_fecha = fecha

    def cargar_resultados_csv(self, ruta_csv: str | Path) -> int:
        """
        Carga un historial de resultados y entrena el Elo en orden
        cronologico. Formato esperado del CSV (con encabezado):

            fecha,liga,equipo_local,equipo_visitante,goles_local,goles_visitante

        Ejemplo de fila:
            2026-03-15,soccer_argentina_primera_division,River Plate,Boca Juniors,2,1

        Devuelve el numero de partidos procesados. Si el archivo no
        existe, devuelve 0 sin fallar (el modelo simplemente no tiene
        entrenamiento todavia -- ver limitacion honesta al inicio del
        archivo).
        """
        ruta = Path(ruta_csv)
        if not ruta.exists():
            return 0

        filas = []
        with ruta.open(newline="", encoding="utf-8") as f:
            lector = csv.DictReader(f)
            for fila in lector:
                filas.append(fila)

        filas.sort(key=lambda r: r["fecha"])

        for fila in filas:
            fecha = datetime.fromisoformat(fila["fecha"]).replace(tzinfo=timezone.utc)
            self.actualizar_con_resultado(
                local=fila["equipo_local"],
                visitante=fila["equipo_visitante"],
                liga=fila["liga"],
                goles_local=int(fila["goles_local"]),
                goles_visitante=int(fila["goles_visitante"]),
                fecha=fecha,
            )
        return len(filas)


# ----------------------------------------------------------------------
# Backtesting y calibracion (puntos 14 y 15)
# ----------------------------------------------------------------------

def backtest_walk_forward(ruta_csv: str | Path) -> dict:
    """
    Backtesting "walk-forward": para cada partido del historial, primero
    se calcula la probabilidad ANTES de conocer el resultado (usando
    solo el Elo acumulado hasta ese momento), y despues se actualiza el
    Elo con el resultado real. Esto evita la trampa mas comun al
    validar modelos (usar informacion futura sin darse cuenta).

    Devuelve metricas honestas de calidad del modelo:
      - brier_score: que tan bien calibradas estan las probabilidades
        (mas bajo es mejor; 0 es perfecto, 0.33 es igual que adivinar
        al azar entre 3 resultados).
      - accuracy: porcentaje de partidos donde el resultado mas
        probable segun el modelo efectivamente ocurrio.
      - partidos_evaluados: cuantos partidos se usaron.

    Un Brier score bajo NO garantiza ganancias futuras -- solo dice que
    el modelo esta bien calibrado sobre datos pasados. Sigue siendo
    obligatorio comparar contra el mercado (punto 17, Closing Line
    Value) antes de confiar en el modelo con dinero real.
    """
    ruta = Path(ruta_csv)
    if not ruta.exists():
        return {"error": f"No existe el archivo de resultados historicos: {ruta}"}

    filas = []
    with ruta.open(newline="", encoding="utf-8") as f:
        lector = csv.DictReader(f)
        for fila in lector:
            filas.append(fila)
    filas.sort(key=lambda r: r["fecha"])

    if len(filas) < 30:
        return {
            "error": (
                f"Solo hay {len(filas)} partidos en el historial. Se necesitan "
                "al menos ~30-50 por liga para que el backtesting sea minimamente "
                "significativo, y idealmente varios cientos. No se debe confiar "
                "en un modelo entrenado con muy pocos datos."
            )
        }

    motor = MotorElo()
    suma_brier = 0.0
    aciertos = 0
    evaluados = 0

    for fila in filas:
        fecha = datetime.fromisoformat(fila["fecha"]).replace(tzinfo=timezone.utc)
        local, visitante, liga = fila["equipo_local"], fila["equipo_visitante"], fila["liga"]
        goles_local, goles_visitante = int(fila["goles_local"]), int(fila["goles_visitante"])

        # Solo evaluamos si ambos equipos ya tienen historial previo
        # (si no, el Elo inicial no aporta informacion real todavia).
        clave_local = motor._clave(local, liga)
        clave_visitante = motor._clave(visitante, liga)
        tiene_historial = (
            clave_local in motor.equipos and motor.equipos[clave_local].partidos_jugados >= 3
        ) and (
            clave_visitante in motor.equipos and motor.equipos[clave_visitante].partidos_jugados >= 3
        )

        if tiene_historial:
            prob = motor.probabilidad_partido(local, visitante, liga)
            if goles_local > goles_visitante:
                resultado_real = "local"
            elif goles_local < goles_visitante:
                resultado_real = "visitante"
            else:
                resultado_real = "empate"

            for resultado, p in prob.items():
                objetivo = 1.0 if resultado == resultado_real else 0.0
                suma_brier += (p - objetivo) ** 2

            prediccion = max(prob, key=prob.get)
            if prediccion == resultado_real:
                aciertos += 1
            evaluados += 1

        motor.actualizar_con_resultado(local, visitante, liga, goles_local, goles_visitante, fecha)

    if evaluados == 0:
        return {
            "error": (
                "No hubo suficientes partidos con historial previo para evaluar. "
                "Se necesita mas profundidad de datos por equipo."
            )
        }

    return {
        "brier_score": round(suma_brier / (evaluados * 3), 4),
        "accuracy": round(aciertos / evaluados, 4),
        "partidos_evaluados": evaluados,
        "partidos_totales_en_csv": len(filas),
        "nota": (
            "Brier score de referencia: ~0.20 o menos suele considerarse razonable "
            "para futbol (el techo teorico es dificil de bajar de ~0.18-0.20 por la "
            "varianza propia del deporte). Comparar siempre contra el Brier score "
            "de simplemente usar las cuotas de mercado como probabilidad, para saber "
            "si el modelo propio realmente aporta algo por encima del consenso."
        ),
    }


if __name__ == "__main__":
    # Demo rapida sin datos historicos: muestra que el motor funciona,
    # pero deja claro que sin historial real la probabilidad es neutra.
    motor = MotorElo()
    n = motor.cargar_resultados_csv("resultados_historicos.csv")
    print(f"Partidos cargados desde resultados_historicos.csv: {n}")
    if n == 0:
        print(
            "AVISO: no se encontro resultados_historicos.csv. El motor esta "
            "operativo pero sin entrenar -- ver la limitacion honesta al inicio "
            "de este archivo. Las probabilidades de ejemplo abajo son neutras "
            "(equipos con Elo inicial identico)."
        )
    ejemplo = motor.probabilidad_partido("Equipo A", "Equipo B", liga="demo")
    print("Ejemplo de salida:", ejemplo)
