from fastapi import APIRouter, Depends
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import SocialMention
from ..schemas import MentionIn

router = APIRouter(prefix="/mentions", tags=["mentions"])


@router.post("", status_code=201)
def ingest_mention(payload: MentionIn, db: Session = Depends(get_db)):
    """Recibe posteos crudos del scraper de X (seccion 5.1). Deduplica por
    (source_account, external_id): si el scraper reintenta un posteo ya
    ingerido, no rompe ni duplica."""
    mention = SocialMention(
        source_account=payload.source_account,
        external_id=payload.external_id,
        raw_text=payload.raw_text,
        posted_at=payload.posted_at,
        status="pending",
    )
    db.add(mention)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        return {"status": "duplicate"}

    return {"status": "ok"}
