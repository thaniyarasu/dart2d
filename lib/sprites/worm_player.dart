library playersprites;

import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/gamestate.dart';
import 'dart:math';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/weapons/weapon_state.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/sprites/stickysprite.dart';
import 'package:dart2d/sprites/rope.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:html';

/**
 * Created on the server and streamed from the client.
 * How the servers represents remote clients.
 */
class RemotePlayerServerSprite extends LocalPlayerSprite {
  RemotePlayerServerSprite(
      World world, KeyState keyState, PlayerInfo info, double x, double y, int imageIndex)
      : super(world, keyState, info, x, y, imageIndex);
  
  RemotePlayerServerSprite.copyFromMovingSprite(
      World world, KeyState keystate, PlayerInfo info, MovingSprite sprite)
      : super.copyFromMovingSprite(sprite) {
    this.world = world;
    this.info = info;
    this.keyState = keystate;
    this.collision = this.inGame;
    this.health = LocalPlayerSprite.MAX_HEALTH; // TODO: Make health part of the GameState.
    this.networkId = sprite.networkId;
  }

  void checkControlKeys(double duration) {
    // Don't execute remote movements on the server.
  }
}

/**
 * A version of the PlayerSprite created in the client and sent to the server.
 * How the client represents itself.
 */
class RemotePlayerSprite extends LocalPlayerSprite {
  RemotePlayerSprite(World world, KeyState keyState, double x, double y, int imageIndex)
      : super(world, keyState, null, x, y, imageIndex);
  
  void fire() {
    // Don't do anything in the local client.
  }
}

/**
 * How a server represents itself.
 */
class LocalPlayerSprite extends MovingSprite {
  static const BOUCHYNESS = 0.3;
  static final Vec2 DEFAULT_PLAYER_SIZE = new Vec2(40.0, 40.0);
  static int MAX_HEALTH = 100;
  static const double RESPAWN_TIME = 3.0;
  static const MAX_SPEED = 500.0;
  
  Map<String, int> _controls = {
      "Left": KeyCode.LEFT,
      "Right": KeyCode.RIGHT,
      "Aim up": KeyCode.UP,
      "Aim down": KeyCode.DOWN,
      "Jump": KeyCode.F,
      "Fire": KeyCode.D,
      "Rope": KeyCode.R,
      "Next weapon": KeyCode.G,
      "Prev weapon": KeyCode.B,
  };

  WormWorld world;
  int health = MAX_HEALTH;
  PlayerInfo info;
  Rope rope;
  KeyState keyState;
  WeaponState weaponState;
  
  bool onGround = false;
    
  bool inGame = true;
  double spawnIn = 0.0;
  
  MovingSprite gun;

  factory LocalPlayerSprite.copyFromRemotePlayerSprite(RemotePlayerSprite convertSprite) {
    LocalPlayerSprite sprite = new LocalPlayerSprite.copyFromMovingSprite(convertSprite);
    sprite.world = convertSprite.world;
    sprite.info = convertSprite.info;
    sprite.keyState = convertSprite.keyState;
    sprite.collision = convertSprite.inGame;
    sprite.health = convertSprite.health;
    sprite.networkId = convertSprite.networkId;
    sprite.networkType = NetworkType.LOCAL;
    return sprite;
  }
  
  LocalPlayerSprite.copyFromMovingSprite(MovingSprite convertSprite)
       : super.withVecPosition(convertSprite.position, convertSprite.imageIndex) {
     this.collision = inGame;
     this.size = convertSprite.size;
     this.networkId = convertSprite.networkId;
     this.networkType = convertSprite.networkType;
   }
  
  LocalPlayerSprite(World world, KeyState keyState, PlayerInfo info, double x, double y, int imageIndex)
      : super(x, y, imageIndex) {
    this.world = world;
    this.info = info;
    this.keyState = keyState;
    this.collision = inGame;
    this.size = DEFAULT_PLAYER_SIZE;
    this.gun = new StickySprite(this, imageByName["gun.png"], Sprite.UNLIMITED_LIFETIME, 30, 7);
    this.weaponState = new WeaponState(world, keyState, this, this.gun);
    this.listenFor("Next weapon", () {
      weaponState.nextWeapon();
    });
    this.listenFor("Prev weapon", () {
      weaponState.prevWeapon();
    });
  }

  collide(MovingSprite other, ByteWorld world, int direction) {
    if (world != null) {
      if (direction == MovingSprite.DIR_BELOW) {
        onGround = true;
        if (velocity.y > 0) {
          velocity.y = -velocity.y * BOUCHYNESS;
        }
        // Check one more time, but y -1.
        while (world.isCanvasCollide(position.x + 1, position.y + size.y - 1.0, size.x -1, 1)) {
          position.y--;
        }
      }
      if (direction == MovingSprite.DIR_ABOVE) {
        if (velocity.y < 0) {
          velocity.y = -velocity.y * BOUCHYNESS;
        }
      }
      
      if (direction == MovingSprite.DIR_LEFT) {
        if (velocity.x < 0) {
          velocity.x = -velocity.x * BOUCHYNESS;
          position.x++;
        }
      }
      if (direction == MovingSprite.DIR_RIGHT) {
        if (velocity.x > 0) {
          velocity.x = -velocity.x * BOUCHYNESS;
          position.x--;
        }
      }
    }
  }
  
  draw(CanvasRenderingContext2D context, bool debug) {
    if (!inGame) {
      return;
    }
    if (weaponState != null) {
      weaponState.draw(context);
    }
    super.draw(context, debug);
    _drawHealthBar(context);
  }

  _drawHealthBar(CanvasRenderingContext2D context) {
    double healthFactor = health/MAX_HEALTH;
    context.resetTransform();
    var grad = context.createLinearGradient(0, 0, 3*WIDTH*healthFactor, 10);
    grad.addColorStop(0, "#00ff00");
    grad.addColorStop(1, "#FF0000");
    context.globalAlpha = 0.5;
    context.fillStyle = grad;
    context.fillRect(0, HEIGHT - 10, WIDTH * healthFactor, 10);
    context.globalAlpha = 1.0;
  }
  
  frame(double duration, int frames, [Vec2 gravity]) {
    if (!inGame) {
      spawnIn-= duration;
      if (spawnIn < 0) {
        velocity = new Vec2();
        world.hudMessages.displayAndSendToNetwork("${info.name} is back!");
        inGame = true;
        collision = true;
        health = MAX_HEALTH;
      }
      return;
    }
    checkControlKeys(duration);
    super.frame(duration, frames, gravity);
    
    if (weaponState != null) {
      weaponState.think(duration);
    }
    if (velocity.x.abs() < 10.0) {
      this.frameIndex = 0;
    }
  }

  void checkControlKeys(double duration) {
    if (keyIsDown("Left")) {
      if (velocity.x > -100) {
        velocity.x -= 20.0;
      } if (velocity.x < -100) {
        velocity.x = -100.0;
      }
      if (angle <  PI * 2) {
        gun.angle -= (gun.angle + PI / 2) * 2;
        angle = PI * 2 + 0.01;
      }
    } else if (keyIsDown("Right")) {
      if (velocity.x < 100) {
        velocity.x += 20.0;
      } if (velocity.x > 100) {
        velocity.x = 100.0;
      }
      if (angle != 0.0) {
        angle = 0.0;
        gun.angle -= (gun.angle + PI / 2) * 2;
      }
    } else {
      velocity.x = velocity.x * 0.94; 
    }
    
    if (keyState.keyIsDown(KeyCode.F) && rope != null) {
      world.removeSprite(rope.networkId);
      rope = null;
    }
    
    if (keyState.keyIsDown(KeyCode.F) && onGround) {
      this.velocity.y -= 200.0; 
      this.onGround = false;
     
    } else if (keyIsDown("Aim down")) {
      gunDown(duration);
    } else if (keyIsDown("Aim up")) {
      gunUp(duration);
    }
    
    if (keyIsDown("Fire")) {
      weaponState.fire();
    }
    
    if (keyIsDown("Rope")) {
      fireRope();
    }
  }
  
  void gunDown(double duration) {
    if (angle != 0.0) {
      gun.angle -= duration * 2.0;
      if (gun.angle < -(PI + PI/3)) {
        gun.angle = -(PI + PI/3);
      }
    } else {
      gun.angle += duration * 2.0;
      if (gun.angle > PI/3) {
        gun.angle = PI / 3;
      }
    }
  }
  
  void gunUp(double duration) {
    // Diffent if facing left or right.
    if (angle != 0.0) {
      gun.angle += duration * 2.0;
      if (gun.angle > -PI/2) {
        gun.angle = -PI/2;
      }
    } else {
      gun.angle -= duration * 2.0;
      if (gun.angle < -PI/2) {
        gun.angle = -PI/2;
      }
    }
  }
  
  void fireRope() {
    if (rope != null) {
      world.removeSprite(rope.networkId);
    }
    rope = new Rope.createWithOwner(this.world.byteWorld, this, this.gun.angle, 600.0);
    world.addSprite(rope);
  }

  bool takesDamage() {
    return true;
  }
  
  void takeDamage(int damage) {
    health -= damage;
    if (health <= 0) {
      world.hudMessages.displayAndSendToNetwork("${info.name} died!");
      info.deaths++;
      inGame = false;
      collision = false;
      spawnIn = RESPAWN_TIME;  
    }
  }
  
  void listenFor(String key, dynamic f) {
    assert(_controls.containsKey(key));
    keyState.registerListener(_controls[key], f);
  }
  
  bool keyIsDown(String key) {
    assert(_controls.containsKey(key));
    return keyState.keyIsDown(_controls[key]);
  }
}