#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="/home/dev/.local/jdk/bin:$PATH"

LIB_DIR="$SCRIPT_DIR/libs"
mkdir -p "$LIB_DIR" "$SCRIPT_DIR/out"

HIKARI_VER="5.1.0"
SLF4J_VER="2.0.12"
PG_VER="42.7.3"

MAVEN="https://repo1.maven.org/maven2"

# 의존성 jar 파일이 없으면 Maven Central에서 다운로드한다.
download_jar() {
    local dest="$1"
    local url="$2"
    if [[ ! -f "$dest" ]]; then
        echo "Downloading $(basename "$dest") ..."
        curl -fsSL "$url" -o "$dest"
    fi
}

# HikariCP: JDBC 커넥션 풀 구현체
download_jar "$LIB_DIR/HikariCP-${HIKARI_VER}.jar" \
    "${MAVEN}/com/zaxxer/HikariCP/${HIKARI_VER}/HikariCP-${HIKARI_VER}.jar"

# slf4j-api: HikariCP 내부 로깅 인터페이스 의존성
download_jar "$LIB_DIR/slf4j-api-${SLF4J_VER}.jar" \
    "${MAVEN}/org/slf4j/slf4j-api/${SLF4J_VER}/slf4j-api-${SLF4J_VER}.jar"

# slf4j-nop: 로그 출력을 억제하는 no-op 바인딩 (콘솔 노이즈 제거)
download_jar "$LIB_DIR/slf4j-nop-${SLF4J_VER}.jar" \
    "${MAVEN}/org/slf4j/slf4j-nop/${SLF4J_VER}/slf4j-nop-${SLF4J_VER}.jar"

# PostgreSQL JDBC 드라이버 (Oracle 사용 시 ojdbc11.jar로 교체하고 아래 CP에서 경로를 수정한다)
download_jar "$LIB_DIR/postgresql-${PG_VER}.jar" \
    "${MAVEN}/org/postgresql/postgresql/${PG_VER}/postgresql-${PG_VER}.jar"

# 기존 Redis 의존성 (Jedis + commons-pool2)
JEDIS_VER="5.2.0"
POOL_VER="2.12.0"
download_jar "$LIB_DIR/jedis-${JEDIS_VER}.jar" \
    "${MAVEN}/redis/clients/jedis/${JEDIS_VER}/jedis-${JEDIS_VER}.jar"
download_jar "$LIB_DIR/commons-pool2-${POOL_VER}.jar" \
    "${MAVEN}/org/apache/commons/commons-pool2/${POOL_VER}/commons-pool2-${POOL_VER}.jar"

CP="${LIB_DIR}/HikariCP-${HIKARI_VER}.jar"
CP="${CP}:${LIB_DIR}/slf4j-api-${SLF4J_VER}.jar"
CP="${CP}:${LIB_DIR}/slf4j-nop-${SLF4J_VER}.jar"
CP="${CP}:${LIB_DIR}/postgresql-${PG_VER}.jar"
CP="${CP}:${LIB_DIR}/jedis-${JEDIS_VER}.jar"
CP="${CP}:${LIB_DIR}/commons-pool2-${POOL_VER}.jar"

echo "Compiling Java 21 Virtual Thread Server..."
javac -cp "$CP" "$SCRIPT_DIR/VirtualServer.java" -d "$SCRIPT_DIR/out"
echo "Build complete"

# 런타임 실행 시 동일한 클래스패스를 참조할 수 있도록 .classpath 파일에 기록한다.
echo "$CP" > "$SCRIPT_DIR/.classpath"
