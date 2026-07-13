from typing import Optional

import anthropic

from .config import settings

_client: Optional[anthropic.Anthropic] = None


def get_client() -> anthropic.Anthropic:
    global _client
    if _client is None:
        _client = anthropic.Anthropic(api_key=settings.anthropic_api_key)
    return _client


RISK_CLASSIFICATION_TOOL = {
    "name": "record_risk_classification",
    "description": "Registra la clasificacion estructurada de un reporte de riesgo.",
    "input_schema": {
        "type": "object",
        "properties": {
            "category": {
                "type": "string",
                "enum": ["asalto", "robo_de_auto", "zona_oscura_sin_gente", "disturbio", "otro", "no_relevante"],
            },
            "score": {
                "type": "number",
                "description": "Score de riesgo de 0 (sin riesgo) a 100 (riesgo maximo)",
            },
            "confidence": {"type": "number", "description": "Confianza de 0 a 1 en la clasificacion"},
        },
        "required": ["category", "score", "confidence"],
    },
}

MENTION_EXTRACTION_TOOL = {
    "name": "record_mention_extraction",
    "description": "Extrae los datos estructurados de una mencion de incidente en redes sociales.",
    "input_schema": {
        "type": "object",
        "properties": {
            "is_incident": {
                "type": "boolean",
                "description": "true solo si el posteo reporta un incidente de seguridad real y reciente "
                "(no sarcasmo, no publicidad, no repost viejo sin contexto de fecha)",
            },
            "incident_type": {
                "type": "string",
                "enum": ["asalto", "robo_de_auto", "zona_oscura_sin_gente", "disturbio", "otro"],
            },
            "location_text": {
                "type": "string",
                "description": "Direccion o interseccion mencionada, en formato buscable "
                "(ej. 'Av. Rivadavia y Boyaca, CABA'). Vacio si no se menciona ninguna ubicacion.",
            },
            "confidence": {"type": "number", "description": "Confianza de 0 a 1"},
        },
        "required": ["is_incident", "confidence"],
    },
}


def _call_tool(prompt: str, tool: dict) -> dict:
    client = get_client()
    response = client.messages.create(
        model=settings.claude_model,
        max_tokens=1024,
        tools=[tool],
        tool_choice={"type": "tool", "name": tool["name"]},
        messages=[{"role": "user", "content": prompt}],
    )
    for block in response.content:
        if block.type == "tool_use":
            return block.input
    raise ValueError("Claude no devolvio una respuesta estructurada")


def classify_report(description: Optional[str], incident_type: Optional[str], severity: Optional[str]) -> dict:
    """Capa A: convierte un reporte de texto libre en un score de riesgo
    estructurado (seccion 3.1 del spec)."""
    prompt = (
        "Sos un analista de seguridad vial para AMBA (Buenos Aires, Argentina). "
        "Clasifica el siguiente reporte de un usuario sobre una zona de riesgo.\n\n"
        f"Tipo reportado por el usuario: {incident_type or 'no especificado'}\n"
        f"Gravedad reportada por el usuario: {severity or 'no especificada'}\n"
        f"Descripcion: {description or '(sin descripcion, solo se marco la ubicacion)'}\n\n"
        "Asigna una categoria, un score de riesgo de 0 a 100, y tu confianza en la clasificacion."
    )
    return _call_tool(prompt, RISK_CLASSIFICATION_TOOL)


def extract_mention(raw_text: str, account_name: str) -> dict:
    """Capa A: convierte un posteo crudo de X en datos de incidente
    estructurados (seccion 5.1 del spec)."""
    prompt = (
        f"Sos un analista que revisa posteos de la cuenta comunitaria de AMBA '@{account_name}' "
        "para detectar reportes de inseguridad en tiempo real. Analiza el siguiente posteo y "
        "extrae los datos. Si es sarcasmo, publicidad, o no describe un incidente real y reciente, "
        "marca is_incident=false.\n\n"
        f"Posteo: {raw_text}"
    )
    return _call_tool(prompt, MENTION_EXTRACTION_TOOL)
