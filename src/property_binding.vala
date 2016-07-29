// This is only convenience class as it needs to fit some additional
// features in GBinding which does not support manual transfer or
// suspending
namespace G
{
	[Flags]
	public enum BindFlags
	{
		DEFAULT,
		SYNC_CREATE,
		BIDIRECTIONAL,
		INVERT_BOOLEAN,
		// controls direction of SYNC_CREATE, default is source to target,
		// if this is specified it assumes pipeline is from target to source
		// also controls direction when binding is not BIDIRECTIONAL
		REVERSE_DIRECTION,
		// specifies all binding is done externally and Binding will just be
		// used trough update_from_source and update_from_target
		MANUAL_EVENTS_FROM_SOURCE, //TODO handling
		MANUAL_EVENTS_FROM_TARGET, //TODO handling
		MANUAL_UPDATE = MANUAL_EVENTS_FROM_SOURCE | MANUAL_EVENTS_FROM_TARGET,
		// specifies active status and is update by freeze/unfreeze
		// Binding created with this flag must call unfreeze manually
		//
		// when this flag state changes SYNC_CREATE is processed. if that was
		// due to calling freeze()/unfreeze() SYNC_CREATE is processed again
		INACTIVE,
		// NOTE! flood data detection is disabled by default
		//
		// detects data flood and emits signal flood_detected to enable gui
		// to reflect that state. once flood is over flood_stopped is emited
		// and last data transfer is processed
		//
		// control of data flood detection is done by
		// - flood_detection    (bool) enable/disable this flag in binding
		// - flood_interval     (uint) which specifies minimum interval between
		//                             processing data transfers
		// - flood_enable_after (uint) defines how many events should be processed
		//                             before flooding takes effect
		//
		// main purpose of flood detection is having option to detect when gui 
		// updates would be hogging cpu in some unwanted manner
		//
		// there are lot of cases when spaming is normal behaviour like having 
		// tracking process of something like current frame in animation or 
		// having job status actively updated. but, there are a lot of cases 
		// when this is not wanted like for example when you scroll over list
		// of objects, spaming gui updates is not really something useful unless
		// hogging cpu is desired action
		SOURCE_UPDATE_FLOOD_DETECTION, //TODO handling
		TARGET_UPDATE_FLOOD_DETECTION, //TODO handling
		FLOOD_DETECTION = SOURCE_UPDATE_FLOOD_DETECTION | TARGET_UPDATE_FLOOD_DETECTION,
		// much like flood detection this provides static delay to data transfer
		// if another event occurs during delay, delay is prolonged for another
		// delay_interval. example usecase is binding search controls where you
		// don't want to spam search requests
		DELAYED;

		public bool HAS_FLOOD_DETECTION()
		{
			return ((this & BindFlags.FLOOD_DETECTION) == BindFlags.FLOOD_DETECTION);
		}

		public bool IS_ACTIVE()
		{
			return ((this & BindFlags.INACTIVE) != BindFlags.INACTIVE);
		}

		public bool IS_DELAYED()
		{
			return ((this & BindFlags.DELAYED) == BindFlags.DELAYED);
		}

		public bool HAS_SYNC_CREATE()
		{
			return ((this & BindFlags.SYNC_CREATE) == BindFlags.SYNC_CREATE);
		}

		public bool IS_REVERSE()
		{
			return ((this & BindFlags.REVERSE_DIRECTION) == BindFlags.REVERSE_DIRECTION);
		}

		public bool IS_BIDIRECTIONAL()
		{
			return ((this & BindFlags.BIDIRECTIONAL) == BindFlags.BIDIRECTIONAL);
		}

		public bool HAS_MANUAL_UPDATE()
		{
			return ((this & BindFlags.MANUAL_UPDATE) == BindFlags.MANUAL_UPDATE);
		}

		public bool HAS_INVERT_BOOLEAN()
		{
			return ((this & BindFlags.INVERT_BOOLEAN) == BindFlags.INVERT_BOOLEAN);
		}
	}

	// result false can also be used differently by skipping value handling. method handler can simply
	// set property value as needed and then return false
	public delegate bool PropertyBindingTransformFunc (BindingInterface binding, Value source_value, ref Value target_value);

	public interface DataFloodDetection : Object
	{
		public abstract bool flood_detection { get; set; }
		public abstract uint flood_interval { get; set; }
		public abstract uint promote_flood_limit { get; set; }

		public signal void flood_detected (BindingInterface binding);
		public signal void flood_stopped (BindingInterface binding);
	}

	public interface BindingInterface : Object
	{
		public abstract Object? source { get; }
		public abstract string source_property { get; }
		public abstract Object? target { get; }
		public abstract string target_property { get; }
		public abstract BindFlags flags { get; }

		public abstract void unbind();

		public signal void dropped (BindingInterface binding);
	}

	public class PropertyBinding : Object, BindingInterface, DataFloodDetection
	{
		// used to avoid delay on sync, no relation with thread safety
		private bool data_sync_in_process = false;

		// only case when this is false is when reference to either source or
		// target is dropped
		private bool is_valid = true;
		private bool unbound = true;
		private bool ref_alive = true;

		// flood detection
		private bool events_flooding = false;
		private int64 last_event = 0;
		private int events_in_flood = 0;
		private bool last_direction_from_source = true;

		private bool delay_active = false;

		// lock counter that prevents updating to happen if not 0, no realtion with thread safety
		// purely internal lock from your self situation
		private int is_locked = 0;

		// freeze counter, set with freeze()/unfreeze()
		private int freeze_counter = 0;

		public bool flood_detection { 
			get { return (_flags.HAS_FLOOD_DETECTION()); } 
			set {
				if (value == true)
					_flags = _flags | BindFlags.FLOOD_DETECTION;
				else
					_flags = _flags & ~(BindFlags.FLOOD_DETECTION);
			}
		}

		public uint flood_interval { get; set; default = 100; }

		private uint _promote_flood_limit = 5;
		public uint promote_flood_limit { 
			get { return (_promote_flood_limit); }
			set { _promote_flood_limit = value; }
		}

		public uint delay_interval { get; set; default = 400; }

		private bool __is_active() 
		{
			return ((freeze_counter == 0) && 
			        ((flags & BindFlags.INACTIVE) != BindFlags.INACTIVE) &&
			         (is_valid == true));
		}

		// same as __is_active except not reflecting
		public bool is_active {
			get { return (__is_active()); }
		}

		private static bool default_transform (Value value_a,
		                                       ref Value value_b)
		{
			if ((value_a.type().is_a(value_b.type()) == true) ||
			    (Value.type_compatible(value_a.type(), value_b.type()) == true)) {
				value_a.copy (ref value_b);
				return (true);
			}

			if ((Value.type_transformable(value_a.type(), value_b.type()) == true) &&
				 (value_a.transform(ref value_b) == true))
				return (true);

			GLib.warning ("%s: Unable to convert a value of type %s to a value of type %s",
			              "default_transform()",
			              value_a.type().name(),
			              value_b.type().name());
			return (false);
		}

		private static bool do_invert_boolean (ref Value val)
		{
			GLib.assert (val.holds(typeof(bool)));

			val.set_boolean (! (val.get_boolean()));
			return (true);
		}

		private StrictWeakReference<Object?>? _source = null;
		public Object? source { 
			get { return (_source.target); }
		}

		private ParamSpec? _source_property = null;
		public string source_property { 
			get { 
				if (_source_property == null)
					return ("");
				return (_source_property.name); 
			}
		}

		private StrictWeakReference<Object?>? _target = null;
		public Object? target { 
			get { return (_target.target); }
		}

		private ParamSpec? _target_property = null;
		public string target_property { 
			get { 
				if (_target_property == null)
					return ("");
				return (_target_property.name); 
			}
		}

		private BindFlags _flags = BindFlags.DEFAULT;
		public BindFlags flags { 
			get { return (_flags); }
		}

		private PropertyBindingTransformFunc? _transform_to = null;
		public PropertyBindingTransformFunc? transform_to {
			get { return (_transform_to); }
		}

		private PropertyBindingTransformFunc? _transform_from = null;
		public PropertyBindingTransformFunc? transform_from {
			get { return (_transform_from); }
		}

		private void initial_data_update()
		{
			if (_flags.HAS_SYNC_CREATE() == false)
				return;
			data_sync_in_process = true;
			if (_flags.IS_REVERSE() == false)
				__update_from_source (!__is_active());
			else
				__update_from_target (!__is_active());
			data_sync_in_process = false;
		}

		private void notify_transfer_from_source (Object obj, ParamSpec prop)
		{
			__update_from_source (false);
		}

		private void notify_transfer_from_target (Object obj, ParamSpec prop)
		{
			__update_from_target (false);
		}

		private void connect_signals()
		{
			if ((__is_active() == false) || (unbound == false))
				return;
			if (_flags.HAS_MANUAL_UPDATE() == true)
				return;
			unbound = false;
			if (source != null)
				if ((_flags.IS_BIDIRECTIONAL() == true) ||
				    (_flags.IS_REVERSE() == false))
					source.notify[source_property].connect (notify_transfer_from_source);
			if (target != null)
				if ((_flags.IS_BIDIRECTIONAL() == true) ||
				    (_flags.IS_REVERSE() == true))
					target.notify[target_property].connect (notify_transfer_from_target);
		}

		private void disconnect_signals()
		{
			if (_flags.HAS_MANUAL_UPDATE() == true)
				return;
			unbound = true;
			if (source != null)
				if ((_flags.IS_BIDIRECTIONAL() == true) ||
				    (_flags.IS_REVERSE() == false))
					source.notify[source_property].disconnect (notify_transfer_from_source);
			if (target != null)
				if ((_flags.IS_BIDIRECTIONAL() == true) ||
				    (_flags.IS_REVERSE() == true))
					target.notify[target_property].disconnect (notify_transfer_from_target);
		}

		public void freeze (bool hard_freeze = false)
		{
			freeze_counter++;
			if (freeze_counter == 1) {
				if (is_valid == true) {
					_flags = flags | BindFlags.INACTIVE;
					notify_property ("is-active");
				}
			}
			if (hard_freeze == true)
				disconnect_signals();
		}

		public bool unfreeze()
		{
			if (freeze_counter <= 0)
				return (true);
			freeze_counter--;
			if (freeze_counter == 0) {
				_flags = flags & ~BindFlags.INACTIVE;
				notify_property ("is-active");
				connect_signals();
				initial_data_update();
			}
			return (__is_active());
		}

		private void target_set_value (bool set_default)
		{
			Value srcval = Value(_source_property.value_type);
			Value tgtval = Value(_target_property.value_type);
			if (set_default == true) {
				unowned Value val1 = _source_property.get_default_value();
				val1.copy(ref srcval);
			}
			else
				source.get_property (source_property, ref srcval);

			bool res = true;
			if (_transform_to != null) {
				res = _transform_to (this, srcval, ref tgtval);
			}
			else {
				// do not check types or validity here, fix initialization so it won't happen
				default_transform (srcval, ref tgtval);
				if (_flags.HAS_INVERT_BOOLEAN() == true)
					do_invert_boolean (ref tgtval);
			}
			if (res == true)
				target.set_property (target_property, tgtval);
		}

		private void source_set_value (bool set_default)
		{
			Value srcval = Value(_source_property.value_type);
			Value tgtval = Value(_target_property.value_type);
			if (set_default == true) {
				unowned Value val1 = _target_property.get_default_value();
				val1.copy(ref tgtval);
			}
			else
				target.get_property (target_property, ref tgtval);

			bool res = true;
			if (_transform_from != null) {
				res = _transform_from (this, tgtval, ref srcval);
			}
			else {
				// do not check types or validity here, fix initialization so it won't happen
				default_transform (tgtval, ref srcval);
				if (_flags.HAS_INVERT_BOOLEAN() == true)
					do_invert_boolean (ref srcval);
			}
			if (res == true)
				source.set_property (source_property, srcval);
		}

		private bool flood_timeout()
		{
			if (data_sync_in_process == true)
				return (false);
			int64 ctime = GLib.get_monotonic_time()/1000;
			if (ctime > (last_event+flood_interval)) {
				events_flooding = false;
				events_in_flood = 0;
				flood_stopped (this);

				// since it is unknown if this flood resulted in manual or automatic
				// process, it is best to just update this with all checks. the fact
				// that direction is random, handling it with freeze()/unfreeze() and
				// relying on SYNC_CREATE is not possible
				if (last_direction_from_source == true)
					update_from_source();
				else
					update_from_target();
				return (false);
			}
			return (true);
		}

		private bool process_flood (bool from_source)
		{
			// handle flood if needed
			if (_flags.HAS_FLOOD_DETECTION() == true) {
				int64 current_time = GLib.get_monotonic_time()/1000;
				if (events_flooding == true) {
					last_direction_from_source = from_source;
					last_event = current_time;
					return (false);
				}
				if ((last_event + flood_interval) > current_time) {
					last_event = current_time;
					events_in_flood++;
					if (events_in_flood >= _promote_flood_limit) {
						events_flooding = true;
						flood_detected (this);
						GLib.Timeout.add ((flood_interval), flood_timeout, GLib.Priority.DEFAULT);
						return (false);
					}
				}
				else
					last_event = current_time;
			}
			return (true);
		}

		private bool delay_timeout()
		{
			int64 ctime = GLib.get_monotonic_time()/1000;
			if (ctime > (last_event+delay_interval)) {
				// since it is unknown if this delay resulted in manual or automatic
				// process, it is best to just update this with all checks. the fact
				// that direction is random, handling it with freeze()/unfreeze() and
				// relying on SYNC_CREATE is not possible
				data_sync_in_process = true;
				if (last_direction_from_source == true)
					update_from_source();
				else
					update_from_target();
				data_sync_in_process = false;
				delay_active = false;
				return (false);
			}
			return (true);
		}

		private bool process_delay (bool from_source)
		{
			if (data_sync_in_process == true)
				return (true);
			if (_flags.IS_DELAYED() == true) {
				int64 current_time = GLib.get_monotonic_time()/1000;
				last_direction_from_source = from_source;
				last_event = current_time;
				if (delay_active == false) {
					delay_active = true;
					GLib.Timeout.add ((delay_interval), delay_timeout, GLib.Priority.DEFAULT);
				}
				return (false);
			}
			return (true);
		}

		private void __update_from_source (bool set_default = false)
		{
			if (target == null)
				return;
			if (((set_default == false) && (__is_active() == false)) || (is_locked > 0))
				return;
			if (process_flood(true) == false)
				return;
			if (process_delay(true) == false)
				return;
			is_locked++;
			target_set_value (set_default);
			is_locked--;
		}

		private void _update_from_source (bool set_default = false)
		{
			if ((source == null) && (set_default == false)) {
				GLib.warning ("Source object %s is not alive", _source_property.owner_type.name());
				return;
			}
			if (target == null) {
				GLib.warning ("Target object %s is not alive", _target_property.owner_type.name());
				return;
			}
			if ((_target_property.flags & ParamFlags.WRITABLE) != ParamFlags.WRITABLE) {
				GLib.warning ("Property (target) %s.\"%s\" is not writable", _target_property.owner_type.name(), target_property);
				return;
			}
			if ((set_default == false) && ((_source_property.flags & ParamFlags.READABLE) != ParamFlags.READABLE)) {
				GLib.warning ("Property (source) %s.\"%s\" is not readable", _source_property.owner_type.name(), source_property);
				return;
			}
			__update_from_source (set_default);
		}

		public void update_default_from_source()
		{
			_update_from_source (true);
		}

		public void update_from_source()
		{
			_update_from_source (false);
		}

		private void __update_from_target (bool set_default = false)
		{
			if (source == null)
				return;
			if ((__is_active() == false) || (is_locked > 0))
				return;
			if (process_flood(false) == false)
				return;
			if (process_delay(false) == false)
				return;
			is_locked++;
			source_set_value (set_default);
			is_locked--;
		}

		private void _update_from_target (bool set_default = false)
		{
			if (source == null) {
				GLib.warning ("Source object %s is not alive", _source_property.owner_type.name());
				return;
			}
			if ((target == null) && (set_default == false)) {
				GLib.warning ("Target object %s is not alive", _target_property.owner_type.name());
				return;
			}
			if ((_source_property.flags & ParamFlags.WRITABLE) != ParamFlags.WRITABLE) {
				GLib.warning ("Property (source) %s.\"%s\" is not writable", _source_property.owner_type.name(), source_property);
				return;
			}
			if ((set_default == false) && ((_target_property.flags & ParamFlags.READABLE) != ParamFlags.READABLE)) {
				GLib.warning ("Property (target) %s.\"%s\" is not readable", _target_property.owner_type.name(), target_property);
				return;
			}
			__update_from_target (set_default);
		}

		public void update_default_from_target()
		{
			_update_from_target (true);
		}

		public void update_from_target()
		{
			_update_from_target (false);
		}

		private void initiate_connection()
		{
			if ((source == null) || (target == null))
				return;
			connect_signals();
			initial_data_update();
		}

		// do all safety checking before creation as this will only be valid until imposed fixed conditions
		// are present
		public static PropertyBinding? bind (Object? source, string source_property, Object? target, string target_property, 
		                                     BindFlags bind_flags = BindFlags.DEFAULT, owned PropertyBindingTransformFunc? transform_to = null, 
		                                     owned PropertyBindingTransformFunc? transform_from = null)
		{
			BindFlags flags = bind_flags;
			string srcprop = source_property;
			string tgtprop = target_property;
			bool srcread = false;
			bool srcwrite = false;
			bool tgtread = false;
			bool tgtwrite = false;
			if (source == null) {
				GLib.warning ("Specified source is NULL");
				return (null);
			}
			if (target == null) {
				GLib.warning ("Specified target is NULL");
				return (null);
			}
			if (source == target) {
				GLib.warning ("(source == target), there is probably better way to bind the properties");
				return (null);
			}

			ParamSpec? _source_property = ((ObjectClass) source.get_type().class_ref()).find_property (srcprop);
			ParamSpec? _target_property = ((ObjectClass) target.get_type().class_ref()).find_property (tgtprop);
			if ((_source_property == null) && (PropertyAlias.contains(srcprop) == true)) {
				srcprop = PropertyAlias.get_instance(source_property).safe_get_for (source.get_type(), source_property);
				_source_property = ((ObjectClass) source.get_type().class_ref()).find_property (srcprop);
			}
			if ((_target_property == null) && (PropertyAlias.contains(tgtprop) == true)) {
				tgtprop = PropertyAlias.get_instance(target_property).safe_get_for (target.get_type(), target_property);
				_target_property = ((ObjectClass) target.get_type().class_ref()).find_property (tgtprop);
			}

			if ((_source_property == null) ||
			    ((_source_property.flags & ParamFlags.CONSTRUCT_ONLY) == ParamFlags.CONSTRUCT_ONLY)) {
				GLib.warning ("Type %s (source) does not contain property with name \"%s\"", source.get_type().name(), srcprop);
				return (null);
			}
			if ((_target_property == null) ||
			    ((_target_property.flags & ParamFlags.CONSTRUCT_ONLY) == ParamFlags.CONSTRUCT_ONLY)) {
				GLib.warning ("Type %s (target) does not contain property with name \"%s\"", target.get_type().name(), tgtprop);
				return (null);
			}
			if (flags.IS_BIDIRECTIONAL() == true) {
				srcread = true;
				srcwrite = true;
				tgtread = true;
				tgtwrite = true;
			}
			else if (flags.IS_REVERSE() == true) {
				srcwrite = true;
				tgtread = true;
			}
			else {
				srcread = true;
				tgtwrite = true;
			}
			if ((srcread == true) &&
			    ((_source_property.flags & ParamFlags.READABLE) != ParamFlags.READABLE)) {
				GLib.warning ("Type %s (source) does not contain READABLE property with name \"%s\"", source.get_type().name(), srcprop);
				return (null);
			}
			if ((srcwrite == true) &&
			    ((_source_property.flags & ParamFlags.WRITABLE) != ParamFlags.WRITABLE)) {
				GLib.warning ("Type %s (source) does not contain WRITABLE property with name \"%s\"", source.get_type().name(), srcprop);
				return (null);
			}
			if ((tgtread == true) &&
			    ((_target_property.flags & ParamFlags.READABLE) != ParamFlags.READABLE)) {
				GLib.warning ("Type %s (target) does not contain READABLE property with name \"%s\"", target.get_type().name(), tgtprop);
				return (null);
			}
			if ((tgtwrite == true) &&
			    ((_target_property.flags & ParamFlags.WRITABLE) != ParamFlags.WRITABLE)) {
				GLib.warning ("Type %s (target) does not contain WRITABLE property with name \"%s\"", target.get_type().name(), tgtprop);
				return (null);
			}
			if ((flags.IS_DELAYED() == true) &&
			    (flags.HAS_FLOOD_DETECTION() == true)) {
				GLib.warning ("FLOOD_DETECTION and DELAYED are incompatible. Ignoring FLOOD_DETECTION");
				flags = flags & ~(BindFlags.FLOOD_DETECTION);
			}
			// only do checks on writable parts as boolean might be result of translation
			if (flags.HAS_INVERT_BOOLEAN() == true) {
				if ((srcwrite == true) &&
				    (_source_property.value_type != typeof(bool))) {
					GLib.warning ("Type %s (source) does not contain WRITABLE boolean property with name \"%s\"", source.get_type().name(), srcprop);
					return (null);
				}
				if ((tgtwrite == true) &&
				    (_target_property.value_type != typeof(bool))) {
					GLib.warning ("Type %s (target) does not contain WRITABLE boolean property with name \"%s\"", target.get_type().name(), tgtprop);
					return (null);
				}
			}
			return (new PropertyBinding (source, _source_property, target, _target_property, flags, transform_to, transform_from));
		}

		private void _unbind()
		{
			if (unbound == false) {
				unbound = true;
				disconnect_signals();
			}
		}

		public void unbind()
		{
			_unbind();
			if (ref_alive == true) {
				ref_alive = false;
				unref();
			}
			dropped (this);
		}

		private void handle_source_dead()
		{
			// source is already null here since handling of weak_unref was before dispatching this
			is_valid = false;
			unbind();
		}

		private void handle_target_dead()
		{
			// target is already null here since handling of weak_unref was before dispatching this
			is_valid = false;
			unbind();
		}

		~PropertyBinding()
		{
			_unbind();
		}

		private PropertyBinding (Object? source, ParamSpec? source_property, Object? target, ParamSpec? target_property, 
		                         BindFlags flags = BindFlags.DEFAULT, owned PropertyBindingTransformFunc? transform_to = null, 
		                         owned PropertyBindingTransformFunc? transform_from = null)
		{
			// no need for error checking as it had been done in create() which is only public accessible
			// way of creation

			_source = new StrictWeakReference<Object?> (source, handle_source_dead);
			_target = new StrictWeakReference<Object?> (target, handle_target_dead);

			_source_property = source_property;
			_target_property = target_property;

			_transform_to = (owned) transform_to;
			_transform_from = (owned) transform_from;

			_flags = flags;

			if ((flags & BindFlags.INACTIVE) == BindFlags.INACTIVE)
				freeze_counter = 1;

			initiate_connection();
			// add reference to keep your self alive until unbind
			ref();
		}
	}

	public delegate BindingInterface? CreatePropertyBinding (Object? source, string source_property, Object? target, string target_property,
	                                                         BindFlags flags, owned PropertyBindingTransformFunc? transform_to = null, 
	                                                         owned PropertyBindingTransformFunc? transform_from = null);
	// This is used to control how binding is created. In many cases usual PropertyBinding will not
	// be best solution as it is completely GObject oriented.
	//
	// Sample case for custom binding creation is streaming where what changed, how it changed is
	// completely different than binding two properties together
	public class Binder
	{
		private static Binder _default_binder = null;

		private static BindingInterface? default_create (Object? source, string source_property, Object? target, string target_property,
		                                                 BindFlags flags, owned PropertyBindingTransformFunc? transform_to = null, 
		                                                 owned PropertyBindingTransformFunc? transform_from = null)
		{
			return ((BindingInterface?) PropertyBinding.bind (source, source_property, target, target_property, flags, transform_to, transform_from));
		}

		public static Binder get_default()
		{
			if (_default_binder == null)
				_default_binder = new Binder();
			return (_default_binder);
		}

		// use this to either employ debugging per need or
		// when custom Binder is really needed
		public static void set_default (Binder? binder)
		{
			if (_default_binder == binder)
				return;
			_default_binder = (binder == null) ? new Binder() : binder;
		}

		private CreatePropertyBinding? _binding_create = null;

		public BindingInterface? bind (Object? source, string source_property, Object? target, string target_property,
		                               BindFlags flags, owned PropertyBindingTransformFunc? transform_to = null, 
		                               owned PropertyBindingTransformFunc? transform_from = null)
		{
			BindingInterface? binding = null;
			if (_binding_create != null)
				binding = _binding_create (source, source_property, target, target_property, flags,
				                           transform_to, transform_from);
			else
				binding = default_create (source, source_property, target, target_property, flags,
				                          transform_to, transform_from);

			if (binding != null)
				binding_created (binding);
			return (binding);
		}

		// allows debug tapping in bindings. to debug when binding goes down
		// application should tap into BindingInterface.dropped or it can
		// wrap its own variation of Binder BindingInterface creation
		public signal void binding_created (BindingInterface binding);

		// method supplied by CreatePropertyBinding is expected to do all safety checks.
		// Binder does absolutely nothing to provide safety
		//
		// if supplied method is null, then it will be relayed to PropertyBinding.bind
		public Binder (owned CreatePropertyBinding? binding_create = null)
		{
			_binding_create = (owned) binding_create;
		}
	}

	public class KeyValuePair<K,V> : Object
	{
		public K key { get; private set; }
		public V val { get; private set; }

		public KeyValuePair (K key, V value)
		{
			this.key = key;
			this.val = value;
		}
	}

	public class KeyValueArray<K,V> : ObjectArray<KeyValuePair<K, V>>
	{
	}

	public class MasterSlaveArray<MK,K,V> : KeyValueArray<MK, KeyValueArray<K, V>>
	{
	}

	public class AliasArray : MasterSlaveArray<string, Type, string>
	{
	}

	private static void add_alias (string s, AliasArray list)
	{
		KeyValueArray<Type, string> prop_list = new KeyValueArray<Type, string>();
		PropertyAlias alias = PropertyAlias.get_instance (s);
		alias.foreach_registration ((t, p) => {
			prop_list.add (new KeyValuePair<Type, string> (t, p));
		});
		alias.added_type_alias.connect ((t, p) => {
			prop_list.add (new KeyValuePair<Type, string> (t, p));
		});
		KeyValuePair<string, KeyValueArray<Type, string>> alias_pair = 
			new KeyValuePair<string, KeyValueArray<Type, string>>(s, prop_list);
		list.add (alias_pair);
	}

	public static AliasArray track_property_aliases()
	{
		AliasArray list = new AliasArray();
		PropertyAlias.foreach_alias ((s) => {
			add_alias (s, list);
		});
		PropertyAlias.AliasSignal.get_instance().added_alias.connect ((s) => {
			add_alias (s, list);
		});
		return (list);
	}

	public class PropertyAlias
	{
		internal class AliasSignal
		{
			private static AliasSignal? _instance = null;
			public static AliasSignal get_instance()
			{
				if (_instance == null)
					_instance = new AliasSignal();
				return (_instance);
			}

			public signal void added_alias (string alias_name);
		}

		private static HashTable<string, PropertyAlias> _property_hash = null;

		private HashTable<Type, string> _hash = null;

		private string _name = "";
		public string name {
			get { return (_name); }
		}

		public static bool contains (string property_name)
		{
			if (_property_hash == null)
				init_prop_hash();
			return (_property_hash.get(property_name) != null);
		}

		private static void init_prop_hash()
		{
			if (_property_hash == null)
				_property_hash = new HashTable<string, PropertyAlias>(str_hash, str_equal);
		}

		public static PropertyAlias get_instance (string alias_name)
		{
			if (_property_hash == null)
				init_prop_hash();

			PropertyAlias? props = _property_hash.get (alias_name);
			if (props == null) {
				props = new PropertyAlias (alias_name);
				_property_hash.insert (alias_name, props);
				AliasSignal.get_instance().added_alias (alias_name);
			}
			return (props);
		}

		public PropertyAlias register (Type type, string property)
		{
			string? res = _hash.get (type);
			if (res != null) {
				GLib.warning ("DefaultProperties.register (%s, %s) error. Already registered!", type.name(), property);
				return (this);
			}

			ParamSpec? parm = ((ObjectClass) type.class_ref()).find_property (property);
			if (parm == null) {
				GLib.warning ("DefaultProperties.register (%s, %s) error. Property does not exist!", type.name(), property);
				return (this);
			}

			_hash.insert (type, property);
			added_type_alias (type, property);
			return (this);
		}

		public string safe_get_for (Type type, string original_val)
		{
			string? res = _hash.get (type);
			if (res == null)
				GLib.warning ("DefaultProperties._get_for (%s) error. Already registered!", type.name());
			return ((res != null) ? res : original_val);
		}

		public string? get_for (Type type)
		{
			return (_hash.get (type));
		}

		private static uint type_hash (Type type)
		{
			return (str_hash (type.name()));
		}

		private static bool type_equal (Type type1, Type type2)
		{
			return (type1 == type2);
		}

		internal static void foreach_alias (Func<string> method)
		{
			if (_property_hash != null)
				_property_hash.for_each ((s,p) => {
					method(s);
				});
		}

		internal void foreach_registration (HFunc<Type, string> method)
		{
			if (_hash != null)
				_hash.for_each (method);
		}

		public signal void added_type_alias (Type type, string property_name);

		private PropertyAlias(string name)
		{
			_name = name;
			_hash = new HashTable<Type, string>(type_hash, type_equal);
		}
	}
}
