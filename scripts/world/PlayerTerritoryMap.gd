class_name PlayerTerritoryMap
extends TerritoryProjection

# Legacy compatibility wrapper.
#
# TerritoryProjection is now the dedicated explicit read-model layer for
# territory queries and can be fully rebuilt from canonical inputs.
# Keep this class name so existing consumers can continue to instantiate
# PlayerTerritoryMap without behavior changes during migration.
