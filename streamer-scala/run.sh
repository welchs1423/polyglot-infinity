#!/bin/bash
export PATH="/home/dev/.local/jdk/bin:$PATH"
S3="/home/dev/.cache/coursier/v1/https/repo1.maven.org/maven2/org/scala-lang/scala3-library_3/3.8.3/scala3-library_3-3.8.3.jar"
S2="/home/dev/.cache/coursier/v1/https/repo1.maven.org/maven2/org/scala-lang/scala-library/2.13.18/scala-library-2.13.18.jar"
cd /home/dev/polyglot-infinity
exec java -cp "streamer-scala/server.jar:$S3:$S2" Main
