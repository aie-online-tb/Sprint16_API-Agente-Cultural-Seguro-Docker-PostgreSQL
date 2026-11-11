# Imagen base oficial de Python (ligera)
FROM python:3.12-slim

# Directorio de trabajo dentro del contenedor
WORKDIR /app

# Copiar requirements.txt dentro del contenedor
COPY requirements.txt .

# Instalar las dependencias
RUN pip install -r requirements.txt

# Copiar el código de la API dentro del contenedor
COPY . .

# Puerto documentado (hay que publicarlo con -p al hacer run)
EXPOSE 8000

# Puerto 8000 por defecto; si existe la variable PORT, se usa esa
CMD uvicorn app:app --host 0.0.0.0 --port ${PORT:-8000}
