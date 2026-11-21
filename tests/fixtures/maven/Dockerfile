# Image de test : vérifie que le jar préparé par _java tourne et porte la version.
FROM eclipse-temurin:25-jre
COPY app.jar /app/app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
