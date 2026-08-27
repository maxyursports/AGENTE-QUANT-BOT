"""
Calculadora de Cobertura en Vivo (Hedging Calculator)
=======================================================
Parte del Superagente Quant de MAXYURSPORTS.

Esta calculadora resuelve, con matemática exacta (nada "al ojo"), la
pregunta que hace el usuario en cada situación de cobertura en vivo:

    "¿Cuánto debo apostar en la opción contraria para..."
      (a) ...asegurar la MISMA ganancia sin importar el resultado?
      (b) ...simplemente RECUPERAR lo invertido si el favorito falla?

No inventa probabilidades ni decide si "hay valor": solo hace el álgebra
de la cobertura una vez que TÚ (o el módulo de análisis en vivo) ya
decidieron que vale la pena cubrir.

Uso típico:
    from hedge_calculator import analizar_cobertura
    resultado = analizar_cobertura(
        stake_original=10.0,
        cuota_original=3.0,
        cuota_cobertura=20.0,
    )
    print(resultado)
"""

from dataclasses import dataclass


@dataclass
class ResultadoCobertura:
    stake_original: float
    cuota_original: float
    cuota_cobertura: float

    # Opción A: ganancia garantizada IGUAL sin importar el resultado
    stake_cobertura_ganancia_igual: float
    ganancia_garantizada: float

    # Opción B: cobertura mínima solo para recuperar lo invertido
    stake_cobertura_solo_recuperar: float
    resultado_si_gana_original_con_recuperacion: float

    def resumen(self) -> str:
        return (
            f"--- Cobertura en vivo ---\n"
            f"Apuesta original: {self.stake_original:.2f} @ {self.cuota_original:.2f}\n"
            f"Cuota de cobertura disponible ahora: {self.cuota_cobertura:.2f}\n\n"
            f"OPCIÓN A — Ganancia igual pase lo que pase:\n"
            f"  Apuesta {self.stake_cobertura_ganancia_igual:.2f} a la opción contraria.\n"
            f"  Ganancia garantizada en AMBOS escenarios: {self.ganancia_garantizada:.2f}\n\n"
            f"OPCIÓN B — Solo asegurar que no pierdes nada (cobertura mínima):\n"
            f"  Apuesta {self.stake_cobertura_solo_recuperar:.2f} a la opción contraria.\n"
            f"  Si gana la original, tu ganancia neta es "
            f"{self.resultado_si_gana_original_con_recuperacion:.2f} "
            f"(mayor que en la Opción A).\n"
            f"  Si gana la cobertura, quedas en 0 (ni ganas ni pierdes).\n"
        )


def analizar_cobertura(
    stake_original: float,
    cuota_original: float,
    cuota_cobertura: float,
) -> ResultadoCobertura:
    """
    stake_original   : lo que ya apostaste antes del partido (o al inicio).
    cuota_original    : la cuota a la que apostaste esa selección.
    cuota_cobertura   : la cuota EN VIVO, ahora mismo, de la opción contraria
                        (empate, rival, o "lo que sea que gane si tu pick falla").

    Devuelve un ResultadoCobertura con las dos rutas posibles.
    """
    if stake_original <= 0 or cuota_original <= 1 or cuota_cobertura <= 1:
        raise ValueError(
            "stake_original debe ser > 0 y las cuotas deben ser > 1.0"
        )

    payout_si_gana_original = stake_original * cuota_original

    # --- Opción A: igualar el retorno total en ambos escenarios ---
    # Se busca H tal que: stake_original*cuota_original == H*cuota_cobertura
    # (retorno total igual sin importar cuál de las dos gane)
    stake_cobertura_igual = payout_si_gana_original / cuota_cobertura
    inversion_total_a = stake_original + stake_cobertura_igual
    ganancia_garantizada = payout_si_gana_original - inversion_total_a

    # --- Opción B: cobertura mínima, solo para no perder el capital ---
    # Se busca H tal que: H*cuota_cobertura == stake_original + H  (break-even)
    # => H*(cuota_cobertura - 1) == stake_original
    stake_cobertura_recuperar = stake_original / (cuota_cobertura - 1)
    inversion_total_b = stake_original + stake_cobertura_recuperar
    resultado_si_gana_original_b = payout_si_gana_original - inversion_total_b

    return ResultadoCobertura(
        stake_original=stake_original,
        cuota_original=cuota_original,
        cuota_cobertura=cuota_cobertura,
        stake_cobertura_ganancia_igual=round(stake_cobertura_igual, 2),
        ganancia_garantizada=round(ganancia_garantizada, 2),
        stake_cobertura_solo_recuperar=round(stake_cobertura_recuperar, 2),
        resultado_si_gana_original_con_recuperacion=round(resultado_si_gana_original_b, 2),
    )


if __name__ == "__main__":
    # Ejemplo real: el mismo caso del texto que mandó el usuario
    r = analizar_cobertura(stake_original=10.0, cuota_original=3.0, cuota_cobertura=20.0)
    print(r.resumen())
