# ☁️ CloudShop Serverless

**CloudShop Serverless** es una prueba de concepto de un e-commerce desplegado 100% en la nube utilizando una arquitectura moderna, escalable y sin servidores (Serverless).

Este proyecto demuestra la implementación de **Infraestructura como Código (IaC)** para orquestar servicios de AWS, automatización de despliegues mediante **CI/CD** y la gestión de seguridad en entornos distribuidos.

✅ **Estado del Proyecto:** Completado (MVP Funcional). Arquitectura desplegada y operativa.

---

## ☁️ Características Principales

* **🛒 Frontend Estático en S3:** Tienda web ultrarrápida alojada como sitio estático en Amazon S3, desacoplada del backend.
* **⚡ Backend Serverless (Lambda):** Lógica de negocio bajo demanda escrita en Python. Escala a cero costes cuando no hay tráfico y gestiona picos de ventas automáticamente.
* **💾 Base de Datos NoSQL (DynamoDB):** Persistencia de pedidos en tiempo real con latencia de milisegundos y alta disponibilidad.
* **🤖 Infraestructura como Código (Terraform):** Toda la nube (redes, permisos, funciones, bases de datos) está definida en código (`.tf`), permitiendo replicar o destruir el entorno con un solo comando.
* **🚀 CI/CD Automatizado:** Pipeline de GitHub Actions que despliega automáticamente los cambios de infraestructura y código Python al hacer push a la rama principal.

---

## 🛠️ Stack Tecnológico

### Infraestructura & DevOps
* **IaC:** Terraform (HCL).
* **CI/CD:** GitHub Actions (Validación, Plan y Apply automático).
* **Seguridad:** AWS IAM (Roles y Políticas de mínimo privilegio) y GitHub OIDC (autenticación sin llaves permanentes).
* **State Management:** Terraform State en S3 con bloqueo de concurrencia mediante DynamoDB.

### Backend (AWS)
* **Compute:** AWS Lambda (Python 3.12).
* **Database:** Amazon DynamoDB.
* **API Gateway/URL:** Lambda Function URL pública.
* **SDK:** `boto3` para interacción con servicios AWS.

### Frontend
* **Core:** HTML5, CSS3 y JavaScript (Vanilla).
* **Hosting:** AWS S3 (Static Website Hosting).
* **Integración:** `fetch` API asíncrona para comunicación con el Backend.

---

## 🏗️ Retos Técnicos Superados

### 1. Gestión de CORS y Seguridad de Red
El navegador bloqueaba las peticiones entre el Frontend (S3) y el Backend (Lambda) por seguridad.
* **Reto:** Configurar los encabezados `Access-Control-Allow-Origin` correctamente sin duplicarlos.
* **Solución:** Se implementó una configuración permisiva en la capa de infraestructura (Terraform) permitiendo métodos `OPTIONS` y headers `content-type`, eliminando la configuración manual en el código Python para evitar conflictos de "doble cabecera".

### 2. Permisos IAM y Principio de Mínimo Privilegio
Configuración de roles granulares para evitar el uso de permisos de administrador genéricos.
* **Reto:** La función Lambda fallaba al intentar escribir en la base de datos (Access Denied).
* **Solución:** Creación de una política IAM específica (`iam_policy_document`) inyectada mediante Terraform que otorga permiso `dynamodb:PutItem` exclusivamente en la tabla `ecommerce-orders` y no en el resto de la cuenta.

### 3. Automatización y Bloqueos de Estado (Terraform Lock)
Gestión del estado de la infraestructura en un entorno colaborativo automatizado.
* **Reto:** El pipeline fallaba por condiciones de carrera o procesos "zombies" que dejaban el archivo de estado bloqueado.
* **Solución:** Implementación de una tabla DynamoDB exclusiva para gestionar el `lockID` de Terraform, asegurando que solo un proceso de despliegue ocurra a la vez y permitiendo el desbloqueo forzoso en caso de error crítico.

---

## 📸 Arquitectura y Demo

### Diagrama de Flujo de Datos
1.  Usuario accede a **S3** (Web).
2.  JS envía petición `POST` a **Lambda URL**.
3.  **Lambda** asume Rol IAM.
4.  Lambda escribe datos en **DynamoDB**.
5.  Respuesta `200 OK` vuelve al usuario.

| <img src="URL_DE_TU_CAPTURA_WEB" width="250" alt="Web Tienda" /> | <img src="URL_DE_TU_CAPTURA_DYNAMO" width="250" alt="DynamoDB Item" /> | <img src="URL_DE_TU_CAPTURA_GITHUBACTIONS" width="250" alt="CI/CD Verde" /> |
| :---: | :---: | :---: |
| **Frontend (S3)** | **Base de Datos (DynamoDB)** | **Pipeline (GitHub Actions)** |



---

## 🚀 Cómo ejecutar el proyecto

Este proyecto se despliega automáticamente, pero para replicarlo necesitas:

**1º) Clonar el repositorio:**
```bash
git clone [https://github.com/JMCLABAS/aws-ecommerce-microservices.git](https://github.com/JMCLABAS/aws-ecommerce-microservices.git)
```

**2º) Configurar Secretos en GitHub:** Ir a `Settings > Secrets and variables > Actions` y añadir:
* `AWS_ACCESS_KEY_ID`
* `AWS_SECRET_ACCESS_KEY`

**3º)Desplegar:** Simplemente haz un push a la rama `main`:
```bash
git push origin main
```
GitHub Actions ejecutará terraform `init`, `plan` y `apply` automáticamente.

---
## 📲 Prueba la Aplicación
👉 **[Enlace a la Tienda Serverless](http://mi-web-ecommerce-portfolio-jmclabas.s3-website-eu-west-1.amazonaws.com)**

---
## 👨‍💻 Autor y Contacto

Desarrollado por **Jose María Clavijo Basáñez.**

Si tienes interés en el código, la arquitectura o quieres colaborar, contáctame en:

* **📧 Email: pclavijobasanez@gmail.com**
* **💼 LinkedIn: www.linkedin.com/in/jose-maría-clavijo-basáñez**
