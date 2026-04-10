# melange-keyring

Diretório para a **chave pública** efêmera do Melange.

## Modelo: chave efêmera por build

A chave de assinatura é gerada no início de cada build (local ou CI) e destruída
logo após a compilação dos pacotes APK. Não existe chave de longa duração —
nem secret no GitHub, nem arquivo commitado.

```
[build-packages]
     │
     ├─ melange keygen → melange.rsa (privada, em memória do runner/shell)
     │                   melange.rsa.pub (pública, repassada ao próximo job)
     │
     ├─ melange build  → packages/*.apk  (assinados com melange.rsa)
     │
     └─ shred melange.rsa   ← chave privada destruída aqui
          │
[build-image]
     └─ apko build    → verifica packages/ com melange.rsa.pub
```

## Geração manual (local)

```bash
# Instale melange ou use via Docker
docker run --rm -v "$PWD":/work cgr.dev/chainguard/melange keygen \
  --out-key /work/melange.rsa \
  --out-pub /work/melange.rsa.pub
```

## O que commitar

| Arquivo          | Commitar? |
|------------------|-----------|
| `melange.rsa`    | **NÃO** — ignorado pelo `.gitignore` |
| `melange.rsa.pub`| **NÃO** — efêmera, gerada por build  |
| `README.md`      | Sim                                   |

