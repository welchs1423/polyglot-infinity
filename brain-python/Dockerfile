# ── Stage 1: C++ shared library ─────────────────────────────────────────────
FROM gcc:12 AS cpp-builder
WORKDIR /build
COPY core-cpp/src/calculator.cpp core-cpp/src/matrix.cpp core-cpp/src/matrix.h .
RUN g++ -shared -fPIC -O2 -o libcore.so calculator.cpp matrix.cpp -lstdc++ -lm

# ── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM python:3.11-slim
WORKDIR /app
COPY --from=cpp-builder /build/libcore.so .
COPY core-zig/zig-out/lib/libzigcore.so .
RUN pip install --no-cache-dir fastapi uvicorn pydantic
COPY brain-python/main.py brain-python/core_bridge.py ./
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
