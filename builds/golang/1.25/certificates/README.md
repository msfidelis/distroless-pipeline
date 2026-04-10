# Diretório de CA Bundles

Coloque aqui seus arquivos de CA bundle no formato PEM (`.pem` ou `.crt`).

## Formato aceito

Cada arquivo pode conter **um ou múltiplos certificados** concatenados (formato bundle):

```
-----BEGIN CERTIFICATE-----
MIIBxTCCAW...
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIBxTCCAW...
-----END CERTIFICATE-----
```

## O que acontece durante o build

O Melange processa os bundles em 4 etapas:

1. **split-ca-bundles** — faz o split de cada bundle em certificados `.crt` individuais  
   → instalados em `/usr/local/share/ca-certificates/<bundle_name>-N.crt`

2. **update-ca-certificates** — reconstrói o trust store do sistema  
   → regenera `/etc/ssl/certs/ca-certificates.crt` com todos os CAs (Wolfi + customizados)

3. **install-to-destdir** — copia o bundle consolidado e os certs individuais para o DESTDIR do APK

4. **validate-bundle** — verifica integridade do bundle final com `openssl x509`

## Convenção de nomenclatura

```
<ambiente>-<propósito>.pem
```

Exemplos:
- `prod-internal-ca.pem`
- `staging-mtls-ca.pem`
- `corp-root-ca.crt`

