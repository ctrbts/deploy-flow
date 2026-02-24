# 🛠 REGLAS DE DESARROLLO DEL PROYECTO

## 1. EL ORÁCULO (ADR & SPECS) - PRIORIDAD MÁXIMA
Antes de proponer cualquier cambio estructural o funcional, el agente DEBE:
1.  **Consultar `docs/adr/`**: Para entender las decisiones técnicas ya tomadas (ej. HTMX vs React).
2.  **Consultar `docs/specs/`**: Para validar que la funcionalidad se alinea con los requerimientos del negocio.
3.  **Protocolo de Discrepancia**: Si mi orden contradice un ADR existente, el agente debe señalar la contradicción y preguntar si se desea crear un nuevo ADR para sobrescribir el anterior.

## 2. TECH STACK (Greenfield)
- **Backend:** Python 3.12+ / Django 6.x.
- **Frontend:** Django Templates + HTMX (siguiendo ADR-001) + Tailwind CSS.
- **Base de Datos:** PostgreSQL (Producción) / SQLite (Desarrollo).
- **Testing:** Pytest-django para unitarios e integración.

## 3. WORKFLOW: "DOCUMENT-FIRST"
Para cada nueva `/feature`:
1.  **Análisis:** Leer specs relevantes.
2.  **Decisión:** Si la implementación introduce una nueva librería o cambio de patrón, proponer un borrador en `docs/adr/NNN-titulo.md` usando la plantilla.
3.  **TDD:** Escribir el test -> Fallar -> Implementar -> Pasar.
4.  **Refactor:** Asegurar que no hay lógica de negocio en las vistas; usar `Services` o `Forms`.

## 4. ESTÁNDARES DE CÓDIGO DJANGO
- **Vistas:** Preferir Class-Based Views (CBVs) con `LoginRequiredMixin`.
- **Modelos:** Incluir siempre `created_at`, `updated_at` y `__str__`.
- **HTMX:** Usar atributos `hx-target` y `hx-swap` de forma explícita para evitar confusiones en el DOM.

## 5. REGLAS DE GIT
- **Mensajes:** Seguir convenciones (feat:, fix:, docs:, test:).
- **ADR en Commits:** Si un commit implementa una decisión de arquitectura, debe mencionar el ID del ADR (ej: `feat: implement login with HTMX (Ref ADR-002)`).
