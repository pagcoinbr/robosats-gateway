# Guia de Deploy Verificado para o RoboSats Gateway em Ubuntu Server

## Avaliação da Facilidade de Deploy

- **Nível de Dificuldade:** Fácil (com os pré-requisitos corretos).
- **Conclusão:** O deploy é extremamente simplificado graças a um script de instalação automatizado. Este guia foi verificado através de uma instalação de teste e inclui todos os passos necessários para garantir um processo sem falhas.

---

## Guia Completo de Implementação

#### Pré-requisitos

1.  **Servidor Ubuntu:** Uma instância do Ubuntu Server 22.04 LTS ou mais recente.
2.  **Acesso SSH:** Conexão ao servidor com um usuário que tenha permissões `sudo`.
3.  **Git:** `sudo apt update && sudo apt install git -y` se ainda não estiver instalado.

---

#### Passo 1: Instalar Dependências e Preparar o Ambiente

1.  **Conecte-se ao seu servidor via SSH.**

2.  **Instale o Docker com o script oficial:**
    ```bash
    curl -fsSL https://get.docker.com | sh
    ```

3.  **Instale o Docker Compose e dependências de Python:**
    *O script de instalação usa o `docker-compose` legado, que pode não vir com o Docker e requer pacotes Python adicionais em versões recentes do Ubuntu.*
    ```bash
    sudo apt-get update
    sudo apt-get install -y docker-compose python3-setuptools
    ```

4.  **Adicione seu usuário ao grupo do Docker:**
    *Isso permite executar comandos do Docker sem `sudo`.*
    ```bash
    sudo usermod -aG docker $USER
    ```

5.  **Aplique as novas permissões (IMPORTANTE):**
    *Saia da sessão SSH e conecte-se novamente para que a permissão do grupo Docker seja aplicada.*
    ```bash
    exit
    ```
    Agora, reconecte-se com `ssh seu_usuario@ip_do_servidor`.

---

#### Passo 2: Clonar e Instalar o Gateway

1.  **Clone o seu repositório:**
    ```bash
    git clone https://github.com/pagcoinbr/robosats-gateway.git
    ```

2.  **Entre no diretório:**
    ```bash
    cd robosats-gateway
    ```

3.  **Execute o script de instalação automatizada:**
    ```bash
    ./install-robosats-gateway.sh
    ```
    Este script irá verificar as dependências (e instalar o Tor se necessário), criar um novo diretório `~/robosats-gateway` com todas as configurações, e iniciar os serviços.

---

#### Passo 3: Verificar e Acessar o Gateway

1.  **Navegue até o diretório de instalação que foi criado:**
    ```bash
    cd ~/robosats-gateway
    ```

2.  **Verifique o status dos serviços:**
    ```bash
    ./status.sh
    ```
    Você deverá ver os contêineres `robosats-client`, `nginx`, e `certbot` com o status `Up`.

3.  **Acesse o gateway** pelo navegador usando o IP do seu servidor: `http://ip_do_servidor`

---

## Solução de Problemas

#### Erro: `429 Too Many Requests` (Limite de Taxa do Docker Hub)

-   **Problema:** A instalação pode falhar ao tentar baixar as imagens Docker se o seu servidor compartilhar um IP que excedeu o limite de downloads anônimos do Docker Hub.
-   **Solução:** Faça login no Docker Hub antes de executar o script de instalação. Você precisará de uma conta gratuita do Docker Hub.
    ```bash
    docker login
    ```
    Siga as instruções para inserir seu nome de usuário e senha. Depois de autenticado, execute o script `./install-robosats-gateway.sh` novamente.

---

## Melhores Práticas e Segurança (Altamente Recomendado)

#### 1. Configurar o Firewall (UFW)

1.  **Permita o tráfego essencial (SSH, HTTP, HTTPS):**
    ```bash
    sudo ufw allow OpenSSH
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    ```

2.  **Ative o firewall:**
    ```bash
    sudo ufw enable
    ```

#### 2. Ativar HTTPS com seu Domínio

(As instruções para esta seção permanecem as mesmas)

...

#### 3. Manutenção

(As instruções para esta seção permanecem as mesmas)

...
