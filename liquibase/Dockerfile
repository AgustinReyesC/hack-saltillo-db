# Imagen de Liquibase con el driver JDBC de PostgreSQL.
# El changelog se monta en /liquibase/changelog desde docker-compose.yml.
FROM liquibase/liquibase:4.29

USER root

# Driver oficial de PostgreSQL. Se descarga en tiempo de build.
ADD https://jdbc.postgresql.org/download/postgresql-42.7.4.jar /liquibase/lib/postgresql.jar
RUN chown liquibase:liquibase /liquibase/lib/postgresql.jar

USER liquibase
WORKDIR /liquibase
