import logging
import os
import time

import httpx

from accounts import ACCOUNTS
from state import load_state, save_state

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("rutasegura-scraper")

BACKEND_URL = os.environ.get("BACKEND_URL", "http://backend:8000")
POLL_INTERVAL_SECONDS = int(os.environ.get("POLL_INTERVAL_SECONDS", "1800"))
MAX_TWEETS_PER_ACCOUNT = 20


def scrape_account(username: str, since_id: str | None) -> list:
    """Scraping ligero del timeline publico de una cuenta (seccion 5.1 del
    spec). Import diferido: si snscrape rompe por un cambio en X, falla solo
    esta funcion, no el proceso entero."""
    import snscrape.modules.twitter as sntwitter

    tweets = []
    scraper = sntwitter.TwitterUserScraper(username)
    for i, tweet in enumerate(scraper.get_items()):
        if i >= MAX_TWEETS_PER_ACCOUNT:
            break
        if since_id and str(tweet.id) == since_id:
            break
        tweets.append(tweet)
    return tweets


def ingest(tweet, username: str) -> None:
    payload = {
        "source_account": username,
        "external_id": str(tweet.id),
        "raw_text": tweet.rawContent,
        "posted_at": tweet.date.isoformat(),
    }
    try:
        response = httpx.post(f"{BACKEND_URL}/mentions", json=payload, timeout=10.0)
        response.raise_for_status()
    except httpx.HTTPError as exc:
        logger.warning("No se pudo ingerir tweet %s de @%s: %s", tweet.id, username, exc)


def run_once() -> None:
    if not ACCOUNTS:
        logger.warning("ACCOUNTS esta vacia - completar accounts.py con cuentas verificadas (seccion 5.1).")
        return

    state = load_state()
    for username in ACCOUNTS:
        try:
            tweets = scrape_account(username, state.get(username))
        except Exception as exc:
            logger.error("Fallo el scraping de @%s (posible cambio en la estructura de X): %s", username, exc)
            continue

        for tweet in reversed(tweets):  # ingerir en orden cronologico
            ingest(tweet, username)

        if tweets:
            state[username] = str(tweets[0].id)
            logger.info("@%s: %d posteos nuevos ingeridos", username, len(tweets))

    save_state(state)


if __name__ == "__main__":
    while True:
        run_once()
        logger.info("Durmiendo %ds antes de la proxima corrida...", POLL_INTERVAL_SECONDS)
        time.sleep(POLL_INTERVAL_SECONDS)
