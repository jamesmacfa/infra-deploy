from app import db, app  # Import db and app from your Flask app

with app.app_context():
    db.create_all()