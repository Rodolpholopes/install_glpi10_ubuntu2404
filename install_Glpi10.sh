#!/bin/bash
set -e  # Para o script caso algum comando falhe
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

# Função para exibir a barra de progresso
progress_bar() {
  local current=$1
  local total=$2
  local percent=$((current * 100 / total))
  local bar_length=50
  local filled_length=$((bar_length * percent / 100))
  local bar=$(printf "%-${bar_length}s" "#" | sed "s/ /#/g")

  echo -ne "\r[${bar:0:filled_length}${bar:filled_length}] ${percent}% concluído."
}

# Nome do banco de dados será fixo como 'glpi10'
DB_NAME="glpi10"

# Solicitar nome do usuário, senha do usuário GLPI e senha do root do MariaDB
echo "Informe o nome do usuário GLPI que deseja criar:"
read DB_USER

echo "Informe a senha para o usuário GLPI:"
read -s DB_PASS  # -s para ocultar a senha enquanto é digitada

echo "Informe a senha do usuário root do MariaDB:"
read -s ROOT_PASS  # Senha do root também deve ser oculta

# Solicitar o timezone
echo "Informe o timezone (ex: America/Sao_Paulo):"
read TIMEZONE

# Total de tarefas
TOTAL_TASKS=20
CURRENT_TASK=0

# Atualização do Sistema Operacional
echo "Atualizando o sistema operacional..."
sudo apt update && sudo apt upgrade -y
CURRENT_TASK=$((CURRENT_TASK + 1))
progress_bar $CURRENT_TASK $TOTAL_TASKS

# Instalação de OpenNTPD
echo "Instalando e configurando OpenNTPD..."
sudo apt purge ntp
sudo apt install -y openntpd
sudo service openntpd stop
sudo dpkg-reconfigure tzdata
echo "servers pool.ntp.br" | sudo tee /etc/openntpd/ntpd.conf
sudo systemctl enable openntpd
sudo systemctl start openntpd
CURRENT_TASK=$((CURRENT_TASK + 1))
progress_bar $CURRENT_TASK $TOTAL_TASKS

# Instalação de ferramentas adicionais
echo "Instalando ferramentas adicionais..."
sudo apt install -y xz-utils bzip2 unzip curl vim git
CURRENT_TASK=$((CURRENT_TASK + 1))
progress_bar $CURRENT_TASK $TOTAL_TASKS

# Instalação do Apache e PHP
echo "Instalando Apache e PHP..."
sudo apt install -y apache2 libapache2-mod-php php-soap php-cas php php-{apcu,cli,common,curl,gd,imap,ldap,mysql,xmlrpc,xml,mbstring,bcmath,intl,zip,redis,bz2}
CURRENT_TASK=$((CURRENT_TASK + 1))
progress_bar $CURRENT_TASK $TOTAL_TASKS

# Instalação e configuração do MariaDB
echo "Verificando e instalando MariaDB..."
if ! mysql --version &> /dev/null; then
   sudo apt install -y mariadb-server
else
   echo "MariaDB já está instalado."
fi

sudo mysql_tzinfo_to_sql /usr/share/zoneinfo | sudo mysql -u root -p"$ROOT_PASS" mysql
sudo systemctl restart mariadb
sudo systemctl status mariadb
CURRENT_TASK=$((CURRENT_TASK + 1))
progress_bar $CURRENT_TASK $TOTAL_TASKS

# Criação da base de dados e usuário GLPI no MariaDB
echo "Criando o banco de dados e usuário GLPI..."
sudo mysql -u root -p"$ROOT_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME default CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
GRANT SELECT ON mysql.time_zone_name TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
CURRENT_TASK=$((CURRENT_TASK + 1))
progress_bar $CURRENT_TASK $TOTAL_TASKS

# Configuração do timezone
echo "Configurando o timezone para o banco de dados..."
sudo mysql -u root -p"$ROOT_PASS" <<EOF
SET GLOBAL time_zone = '$TIMEZONE';
EOF
CURRENT_TASK=$((CURRENT_TASK + 1))
progress_bar $CURRENT_TASK $TOTAL_TASKS

# Baixar e mover GLPI para o diretório web
echo "Baixando e instalando GLPI..."
if [ ! -d "/var/www/html/glpi" ]; then
   cd /tmp
   wget -v -O glpi.tgz https://github.com/glpi-project/glpi/releases/download/10.0.16/glpi-10.0.16.tgz
   tar -zxvf glpi.tgz
   sudo mv -v glpi/ /var/www/html/
else
   echo "GLPI já está instalado no diretório /var/www/html/glpi."
fi
CURRENT_TASK=$((CURRENT_TASK + 1))
progress_bar $CURRENT_TASK $TOTAL_TASKS

# Configuração de permissões do GLPI
echo "Configurando permissões do GLPI..."
if [ ! -d "/var/www/html/glpi/files/_log" ]; then
   sudo mkdir -p /var/www/html/glpi/files/_log
fi
sudo chown -Rfv www-data:www-data /var/www/html/glpi/
sudo find /var/www/html/glpi/ -type d -exec chmod -v 755 {} \;
sudo find /var/www/html/glpi/ -type f -exec chmod -v 644 {} \;
sudo chmod -Rv 777 /var/www/html/glpi/files/_log
CURRENT_TASK=$((CURRENT_TASK + 1))
progress_bar $CURRENT_TASK $TOTAL_TASKS

# Configuração do Apache para o GLPI
echo "Configurando o Apache para o GLPI..."
sudo tee /etc/apache2/conf-available/glpi.conf > /dev/null <<EOL
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
EOL
CURRENT_TASK=$((CURRENT_TASK + 1))
progress_bar $CURRENT_TASK $TOTAL_TASKS

# Configuração do PHP
echo "Configurando o PHP..."
sudo sed -i 's/;session.cookie_httponly =/session.cookie_httponly =/' /etc/php/8.3/apache2/php.ini
CURRENT_TASK=$((CURRENT_TASK + 1))
progress_bar $CURRENT_TASK $TOTAL_TASKS

# Habilitar módulos do Apache e reiniciar o serviço
echo "Habilitando módulos do Apache e reiniciando o serviço..."
sudo a2enmod rewrite
sudo a2enconf glpi.conf
sudo systemctl restart apache2
sudo systemctl status apache2
CURRENT_TASK=$((CURRENT_TASK + 1))
progress_bar $CURRENT_TASK $TOTAL_TASKS

# Verificar logs do Apache
echo "Verificando logs do Apache..."
sudo journalctl -xeu apache2
CURRENT_TASK=$((CURRENT_TASK + 1))
progress_bar $CURRENT_TASK $TOTAL_TASKS

# Mensagens finais
echo -e "\nInstalação do GLPI concluída!"
echo "Cola com o pai que o inimigo cai!"
echo "By Diarrury"
