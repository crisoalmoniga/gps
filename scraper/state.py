import json
from pathlib import Path

STATE_FILE = Path(__file__).parent / "data" / "state.json"


def load_state() -> dict[str, str]:
    """Ultimo tweet_id ingerido por cuenta, para no reprocesar en cada corrida."""
    if not STATE_FILE.exists():
        return {}
    return json.loads(STATE_FILE.read_text())


def save_state(state: dict[str, str]) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2))
