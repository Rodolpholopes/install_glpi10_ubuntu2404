#!/bin/bash

# Para o script caso algum comando falhe
set -e
set -x  # Mostra os comandos à medida que são executados

# Verifica se o script está sendo executado como root
if [[ $EUID -ne 0 ]]; then
   echo "Este script precisa ser executado como root. Utilize sudo." 1>&2
   exit 1
fi

# Arquivo de log
LOGFILE="/var/log/install_glpi.log"
exec > >(tee -i $LOGFILE)
exec 2>&1

# Atualização do SO
sudo apt update && sudo apt upgrade -y

# Definindo TimeZone
sudo apt purge ntp
sudo apt install -y openntpd
sudo service openntpd stop
sudo dpkg-reconfigure tzdata
echo "servers pool.ntp.br" | sudo tee /etc/openntpd/ntpd.conf
sudo systemctl enable openntpd
sudo systemctl start openntpd

# Instalação de pacotes necessários
sudo apt install -y xz-utils bzip2 unzip curl vim git apache2 libapache2-mod-php php-soap php php-{apcu,cli,common,curl,gd,imap,ldap,mysql,xmlrpc,xml,mbstring,bcmath,intl,zip,redis,bz2}

# Banco de Dados
sudo apt install -y mariadb-server

# Definindo novo timezone no DB e criando root
sudo mysql_tzinfo_to_sql /usr/share/zoneinfo | sudo mysql -u root -p mysql
sudo systemctl restart mariadb

# Criação de usuário DB glpi
# Solicitar ao usuário o nome do banco de dados
read -p "Digite o nome do banco de dados: " nome_banco

# Validação do nome do banco de dados
if [[ ! "$nome_banco" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "Nome do banco de dados inválido. Use apenas letras, números e sublinhados."
    exit 1
fi

# Solicitar ao usuário o nome do usuário SQL
read -p "Digite o nome do usuario SQL: " nome_user

# Validação do nome do usuário
if [[ ! "$nome_user" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "Nome do usuário inválido. Use apenas letras, números e sublinhados."
    exit 1
fi

# Solicitar ao usuário a senha do usuário SQL
read -p "Digite a senha do usuario SQL: " psswd

# Criar o banco de dados e o usuário
sudo mysql -u root -p <<MYSQL_SCRIPT
CREATE DATABASE $nome_banco DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER '$nome_user'@'localhost' IDENTIFIED BY '$psswd';
GRANT ALL PRIVILEGES ON $nome_banco.* TO '$nome_user'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Baixando o GLPI
cd /tmp
wget -v -O glpi.tgz https://github.com/glpi-project/glpi/releases/download/10.0.16/glpi-10.0.16.tgz
tar -zxvf glpi.tgz
sudo mv -v glpi/ /var/www/html/

# Alterando permissões
sudo chown -Rfv www-data:www-data /var/www/html/glpi/
sudo find /var/www/html/glpi/ -type d -exec chmod -v 755 {} \;
sudo find /var/www/html/glpi/ -type f -exec chmod -v 644 {} \;
sudo chmod -Rv 777 /var/www/html/glpi/files/_log

# Configuração do Apache para o GLPI
sudo bash -c 'cat <<EOF > /etc/apache2/conf-available/glpi.conf
<VirtualHost *:80>
        DocumentRoot /var/www/html/glpi/public
        ErrorLog ${APACHE_LOG_DIR}/glpi-error.log
        CustomLog ${APACHE_LOG_DIR}/glpi-access.log combined
    <Directory /var/www/html/glpi/public>
        AllowOverride All
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)$ index.php [QSA,L]
        Require all granted
    </Directory>
</VirtualHost>
EOF'

# Alteração do arquivo php.ini
sudo sed -i '/^session.cookie_httponly/c\session.cookie_httponly = 1' /etc/php/8.3/apache2/php.ini
sudo sed -i "/^;date.timezone =/c\date.timezone = $(cat /etc/timezone | sed 's/\//\\\//g')" /etc/php/8.3/apache2/php.ini

# Habilitando módulos e reiniciando o Apache
sudo a2enmod rewrite
sudo a2enconf glpi.conf
sudo rm -rf /var/www/html/glpi/install/install.php
sudo systemctl restart apache2
# Mensagens finais
#Cola com o pai que o inimigo cai!"
#"By Diarrury"
