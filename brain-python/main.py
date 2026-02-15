from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def read_root():
    return {"message": "The Brain is thinking...", "status":"active"}

@app.get("/api/analyze")
def analyze_data():
    return {
        "intelligence_score":99,
        "recommendation":"System integration is optimal.",
        "version" : "Python-Brain-v1"
    }