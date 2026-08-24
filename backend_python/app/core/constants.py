from enum import Enum

class RoleEnum(str, Enum):
    ADMIN = "admin"
    ADMINISTRADOR = "administrador"
    MONITOR = "monitor"
    SUPERVISOR = "supervisor"
    CARTOGRAFO = "cartografo"
    CONSULTA = "consulta"
    GERENTE = "gerente"

# Constante del rol admin blindado contra desactivación
ADMIN_ROLES = {"admin", "administrador"}
ADMIN_ROLE_CONSTANT = "admin"

# Jerarquía de roles (orden de autoridad)
ROLE_HIERARCHY = {
    "admin": 100,
    "administrador": 100,
    "gerente": 80,
    "supervisor": 60,
    "monitor": 40,
    "cartografo": 20,
    "consulta": 10
}

def normalize_role(role: str) -> str:
    r = role.strip().lower()
    if r in ("admin", "administrador"):
        return "admin"
    return r

def is_admin(role: str) -> bool:
    return normalize_role(role) in ADMIN_ROLES

def can_manage_role(actor_role: str, target_role: str) -> bool:
    """Verifica si un rol tiene nivel suficiente para gestionar a otro rol"""
    return ROLE_HIERARCHY.get(normalize_role(actor_role), 0) > ROLE_HIERARCHY.get(normalize_role(target_role), 0)
