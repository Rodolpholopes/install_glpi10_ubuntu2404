Script para instalação GLPI 10.0.16 
SO testado, Ubuntu Server 24.04 minimal
instruções:

1- importar arquivo no terminal:
   wget https://raw.githubusercontent.com/Rodolpholopes/install_glpi10_ubuntu2404/refs/heads/main/install_Glpi10.sh
2- fornecer permissão de instalação:
   sudo chmod +x install_Glpi10.sh
3- instalar
   sudo ./install_Glpi10.sh

   O script pausará para que o usuário insira os seguintes dados durante a execução:

1 - Configuração do MariaDb
    Solicitará que o usuário insira time zone
    solicitará Inserir senha sudo, para criação do usuário do Bd
               Inserir nome do usuário do Db
               inserir senha do usuário Db
               Inserir novamente a senha Sudo

# demais configurações, Permissões e dependências serão instaladas automaticamente.
      
    
