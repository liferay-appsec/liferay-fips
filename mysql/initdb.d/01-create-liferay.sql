-- Initializes the Liferay database user on first container start.
-- Adjust the password if you change JNDI_DB_PASSWORD in docker-compose.
DROP USER IF EXISTS 'liferay'@'%';
CREATE USER 'liferay'@'%' 
    IDENTIFIED BY 'liferay' REQUIRE SSL;
GRANT ALL PRIVILEGES ON lportal.* TO 'liferay'@'%';
FLUSH PRIVILEGES;
