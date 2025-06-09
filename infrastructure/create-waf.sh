#!/bin/bash

# ID da sua distribuição CloudFront. 
# Preencha se souber, caso contrário o script tentará encontrar uma.
# Se você tiver mais de uma distribuição, ajuste a lógica para selecionar a correta.
CLOUDFRONT_DISTRIBUTION_ID="" 

# Região para criar o WAF (US-EAST-1 é obrigatório para CloudFront)
AWS_REGION="us-east-1"

echo "Criando o WebACL '${WEBACL_NAME}' na região '${AWS_REGION}'..."
WEBACL_OUTPUT=$(aws wafv2 create-web-acl \
    --cli-input-json file://"${WEBACL_CONFIG_FILE}" \
    --description "${WEBACL_DESCRIPTION}" \
    --region "${AWS_REGION}" 2>&1)

# Verifique se a criação foi bem-sucedida
if echo "${WEBACL_OUTPUT}" | grep -q "ARN"; then
    WEBACL_ARN=$(echo "${WEBACL_OUTPUT}" | grep "ARN" | awk -F'"' '{print $4}')
    WEBACL_ID=$(echo "${WEBACL_OUTPUT}" | grep "Id" | awk -F'"' '{print $4}')
    echo "WebACL criado com sucesso!"
    echo "  ARN: ${WEBACL_ARN}"
    echo "  ID: ${WEBACL_ID}"
else
    echo "Erro ao criar o WebACL:"
    echo "${WEBACL_OUTPUT}"
    rm "${WEBACL_CONFIG_FILE}"
    exit 1
fi

# --- 3. Obtenha o ID da distribuição CloudFront (se não foi fornecido) ---
if [ -z "${CLOUDFRONT_DISTRIBUTION_ID}" ]; then
    echo "Obtendo IDs das distribuições CloudFront..."
    DISTRIBUTIONS_OUTPUT=$(aws cloudfront list-distributions 2>&1)
    
    if echo "${DISTRIBUTIONS_OUTPUT}" | grep -q "Id"; then
        # Este é um exemplo simples que pega o primeiro ID encontrado.
        # SE VOCÊ TIVER MÚLTIPLAS DISTRIBUIÇÕES, AJUSTE ESSA LÓGICA
        # para selecionar a distribuição correta (ex: filtrando por DomainName ou comentando).
        CLOUDFRONT_DISTRIBUTION_ID=$(echo "${DISTRIBUTIONS_OUTPUT}" | grep "Id" | head -n 1 | awk -F'[<>]' '{print $3}')
        
        echo "Distribuição CloudFront encontrada: ${CLOUDFRONT_DISTRIBUTION_ID}"
    else
        echo "Erro ao listar as distribuições CloudFront ou nenhuma encontrada."
        echo "${DISTRIBUTIONS_OUTPUT}"
        rm "${WEBACL_CONFIG_FILE}"
        exit 1
    fi
fi

# --- 4. Construa o ARN da distribuição CloudFront ---
# O ARN da distribuição CloudFront não é retornado diretamente pelo list-distributions,
# mas pode ser construído. O Account ID será detectado automaticamente pelo CLI.
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "${ACCOUNT_ID}" ]; then
    echo "Erro: Não foi possível obter o Account ID. Verifique suas credenciais AWS."
    rm "${WEBACL_CONFIG_FILE}"
    exit 1
fi

CLOUDFRONT_RESOURCE_ARN="arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${CLOUDFRONT_DISTRIBUTION_ID}"
echo "ARN da distribuição CloudFront: ${CLOUDFRONT_RESOURCE_ARN}"

# --- 5. Associe o WebACL à distribuição CloudFront ---
echo "Associando o WebACL à distribuição CloudFront..."
ASSOCIATE_OUTPUT=$(aws wafv2 associate-web-acl \
    --web-acl-arn "${WEBACL_ARN}" \
    --resource-arn "${CLOUDFRONT_RESOURCE_ARN}" \
    --region "${AWS_REGION}" 2>&1)

if [ $? -eq 0 ]; then
    echo "WebACL associado com sucesso à distribuição CloudFront!"
else
    echo "Erro ao associar o WebACL:"
    echo "${ASSOCIATE_OUTPUT}"
    # Opcional: Você pode querer desassociar/deletar o WebACL se a associação falhar.
    # aws wafv2 delete-web-acl ...
    rm "${WEBACL_CONFIG_FILE}"
    exit 1
fi

# --- 6. Limpeza (opcional): remove o arquivo de configuração JSON ---
rm "${WEBACL_CONFIG_FILE}"
echo "Script concluído. Arquivo temporário '${WEBACL_CONFIG_FILE}' removido."
