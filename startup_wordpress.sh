#!/bin/bash

sudo apt update && apt upgrade -y
sudo apt install apache2 -y
sudo systemctl status apache2
sudo apt install php php-mysql mysql-client php-curl php-gd php-xml php-xmlrpc php-zip -y
sudo systemctl restart apache2




cd  /tmp && wget https://wordpress.org/latest.tar.gz
sudo tar -xvf latest.tar.gz
sudo cp -R wordpress /var/www/html/
sudo chown -R www-data:www-data /var/www/html/wordpress/
sudo chmod -R 755 /var/www/html/wordpress/

sudo mkdir /var/www/html/wordpress/wp-content/uploads
sudo chown -R www-data:www-data /var/www/html/wordpress/wp-content/uploads/

sudo systemctl restart apache2





