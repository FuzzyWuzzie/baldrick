package baldrick;

import haxe.ds.IntMap;
import haxe.Serializer;
import haxe.Unserializer;

/**
   The result of calling `loadEntities`
 */
enum LoadResult {
    /**
       The entities loaded appropriately
     */
    Success;

    /**
       The entities loaded but there may be corruption due to a version mismatch
     */
    VersionMismatch;
}

/**
  A group of `Entity`s and the `Processor`s that are used
  to process them in different phases.
*/
@:allow(baldrick.Entity)
class Universe {
    /**
      The entities that belong to this universe
    */
    public var entities:Array<Entity>;

    /**
      The processor phases that belong to this universe
    */
    public var phases:Array<Phase>;

    private var resources: IntMap<Resource>;

    public function new() {
        this.entities = new Array<Entity>();
        this.phases = new Array<Phase>();
        this.resources = new IntMap<Resource>();
    }

    private function match(entity:Entity):Void {
        for(phase in phases) {
            phase.match(entity);
        }
    }

    private function unmatch(entity:Entity):Void {
        for(phase in phases) {
            phase.unmatch(entity);
        }
    }

    /**
      Construct a new entity
      @param components An optional list of starting components
      @return Entity
    */
    public function createEntity(?components:Array<Component>):Entity {
        return new Entity(this, components);
    }

    /**
      Destroys an entity, removing it entirely from this `Universe`
      @param entity The entity to destroy
    */
    public function destroyEntity(entity:Entity) {
        entity.destroy();
    }

    /**
      Construct a phase, adding it to this Universe
      @return Phase
    */
    public function createPhase():Phase {
        return new Phase(this);
    }

    /**
      Unmatch and delete all entities from this universe
    */
    public function destroyAllEntities():Void {
        for(entity in entities) {
            unmatch(entity);
        }
        entities = new Array<Entity>();
    }

    /**
      Store a resource / global component in the Universe
      @param resource the resource with type to set
     */
    public function setResource(resource: Resource): Void {
        resources.set(resource.hashCode(), resource);
        for(phase in phases) {
            phase.applyResources();
        }
    }

    /**
      Get a resource / global component from the Universe. If an instance
      has not yet been set using `setResource`, this will return `null`
      @param type the ID of the resource to retrieve: `{ResourceClass}.HashCode()`
      @return Null<T>
     */
    public function getResourceByID<T: Resource>(type: ResourceTypeID): Null<T> {
        if(!resources.exists(type)) {
            return null;
        }
        return cast(resources.get(type));
    }

    /**
      Get a resource / global component from the Universe. If an instance
      has not yet been set using `setResource`, this will return `null`
      @param cls The class of the resource to retrieve
      @return Null<T>
     */
    public function getResource<T: Resource>(cls: Class<T>): Null<T> {
        var getHashCode: Void -> Int = Reflect.field(cls, 'HashCode');
        return getResourceByID(getHashCode());
    }

    @:keep
    private function hxSerialize(s:Serializer):Void {
        throw 'Universes cannot be serialized, use `saveEntities()`!';
    }

    @:keep
    private function hxUnserialize(u:Unserializer):Void {
        throw 'Universes cannot be unserialized, use `loadEntities()`!';
    }

    /**
       Serialize the entities / state into a string using the Haxe serializer
       
       **Note:** the git version is stored alongside the serialized data to ensure proper entity matching!
       @return String
     */
    public function saveEntities():String {
        var s:Serializer = new Serializer();
        s.useCache = true;
        var version:Null<String> = baldrick.macros.Version.getGitCommitHash();
        s.serialize(version);
        s.serialize(entities);
        return s.toString();
    }

    /**
       Load the entities saved by `saveEntities`, deleting any currently existing ones

       **Note:** the function will 
       @param buf The state generated by `saveEntities`
       @return LoadResult
     */
    public function loadEntities(buf:String):LoadResult {
        var result:LoadResult = LoadResult.Success;

        // destroy the entities so they don't conflict with our new ones
        destroyAllEntities();

        // unserialize!
        var u:Unserializer = new Unserializer(buf);
        var uVersion:Null<String> = u.unserialize();

        if(uVersion != baldrick.macros.Version.getGitCommitHash()) {
            result = LoadResult.VersionMismatch;
        }

        entities = u.unserialize();

        // always ensure unique IDs when loading
        var maxID:Int = -1;
        for(e in entities) {
            if(e.id > maxID) {
                maxID = e.id;
            }
        }
        Entity._nextId = maxID + 1;

        // make sure all the processors know about the entities
        for(e in entities) {
            e.universe = this;
            match(e);
        }

        return result;
    }

    // TODO: load / save resources
}
