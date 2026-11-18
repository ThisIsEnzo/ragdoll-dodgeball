-- ShopCatalog: ассортимент и уровни анлока ультов.
-- Только косметика: скилл не продаётся, платных преимуществ нет.

return {
Balls = {
{ id = "ball_default", name = "Classic", price = 0, color = Color3.fromRGB(255, 197, 61) },
{ id = "ball_mint", name = "Mint", price = 600, color = Color3.fromRGB(124, 255, 79) },
{ id = "ball_azure", name = "Azure", price = 900, color = Color3.fromRGB(46, 155, 255) },
{ id = "ball_magenta", name = "Magenta", price = 1400, color = Color3.fromRGB(255, 79, 216) },
{ id = "ball_void", name = "Void", price = 2200, color = Color3.fromRGB(199, 125, 255) },
{ id = "ball_ember", name = "Ember", price = 3000, color = Color3.fromRGB(255, 90, 77) },
},

UltLevels = { Cannon = 1, Magnet = 15, Wall = 25, Ghost = 30 },
UltOrder = { "Cannon", "Magnet", "Wall", "Ghost" },

UltLabels = {
Cannon = "CANNON",
Magnet = "MAGNET",
Wall = "WALL",
Ghost = "GHOST",
},
}
