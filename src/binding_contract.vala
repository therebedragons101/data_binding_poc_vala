/*
 * read README.md
 */
namespace G
{
	private const string __DEFAULT__ = "**DEFAULT**";
	private const string BINDING_SOURCE_STATE_DATA = "binding-source-state-data";
	private const string BINDING_SOURCE_VALUE_DATA = "binding-source-value-data";

	public delegate bool SourceValidationFunc (Value? source_value);
	public delegate bool CustomBindingSourceStateFunc (BindingPointer? source);
	public delegate T CustomBindingSourceDataFunc<T> (BindingPointer? source_data);

	public const string[] ALL_PROPERTIES = {};

	public static bool report_possible_binding_errors = false;

	public enum BindingReferenceType
	{
		// In normal cases this means WEAK but certain parts need different operation
		// of that and handle it differently (binding pointer can resolve as contract
		// reference type in order to have uniform handling)
		DEFAULT,
		// Default way of handling references and also preferred. Only use strong
		// when there is no other way
		WEAK,
		// binding adds strong reference on data objects for the duration of activity. 
		// this requires binding to be either suspended or disposed in order to release
		// the reference it holds over source and target object
		STRONG
	}

	public enum BindingPointerUpdateType
	{
		// default value for property update is by properties since this is one
		// reliable information that is always specified with binding information
		PROPERTY,
		// not everywhere would be suitable just binding on properties
		//
		// there are a lot of cases when this kind of binding wouldn't fit the purpose
		// well in which case BindingPointer should be created as MANUAL
		// - it might hammer data too much and cause unnecessary utilization
		// - properties just wouldn't have notifications for specified properties.
		// - binding on signals
		// - binding on timers
		MANUAL
	}

	public enum ContractChangeType
	{
		ADDED,
		REMOVED
	}

	public static bool is_binding_pointer (Object? obj)
	{
		if (obj == null)
			return (false);
		return (obj.get_type().is_a(typeof(BindingPointer)) == true);
	}

	private static bool is_same_type (Object? obj1, Object? obj2)
	{
		return (type_is_same_as ((obj1 == null) ? (Type?) null : obj1.get_type(),
		                         (obj2 == null) ? (Type?) null : obj2.get_type()));
	}

	private static bool type_is_same_as (Type? type1, Type? type2)
	{
		if (type1 == type2)
			return (true);
		if ((type1 == null) || (type2 == null))
			return (false);
		return (type1.is_a(type2));
	}

	public class BindingPointer : Object
	{
		private static GLib.Object _SELF = new GLib.Object();
		[Description (nick="Self", blurb="Pointer to it self")]
		protected static GLib.Object SELF {
			get { return (_SELF); }
		}

		private bool data_disposed = false;

		private BindingReferenceType _reference_type = BindingReferenceType.DEFAULT;
		[Description (nick="Reference type", blurb="Specifies reference type for binding pointer")]
		public virtual BindingReferenceType reference_type {
			get {
				if ((data != null) && 
				    (_reference_type == BindingReferenceType.DEFAULT) &&
				    (data.get_type().is_a(typeof(BindingPointer)) == true))
					return (((BindingPointer) data).reference_type);
				return (_reference_type); 
			}
		}

		private BindingPointerUpdateType _update_type = BindingPointerUpdateType.PROPERTY;
		public BindingPointerUpdateType update_type {
			get {
				if ((data != null) && 
				    (data.get_type().is_a(typeof(BindingPointer)) == true))
					return (((BindingPointer) data).update_type);
				return (_update_type); 
			}
		}

		private StrictWeakReference<Object?> _data = null;
		[Description (nick="Data", blurb="Data object pointed by binding pointer")]
		public Object? data { 
			get { return (_data.target); } 
			set {
				if (get_source() != null)
					disconnect_notifications (get_source());
				if (handle_messages == true)
					before_source_change (this, is_same_type(data, value), value);
				unreference_data();
				if (data != null)
					unchain_pointer();
				if (value == this)
					_data = new StrictWeakReference<Object?>(SELF, handle_strict_ref);
				else
					_data = new StrictWeakReference<Object?>(value, handle_strict_ref);
				if (data != null)
					chain_pointer();
				reference_data();
				if (handle_messages == true) {
					source_changed (this);
					}
				if (get_source() != null)
					connect_notifications (get_source());
			}
		}

		protected virtual bool handle_messages {
			get { return ((get_source() != null) && (data_disposed == false)); }
		}

		protected virtual Object? redirect_to (ref bool redirect_in_play)
		{
			redirect_in_play = false;
			return (null);
		}

		// Returns real end of chain value for source object specified in data where
		// result can point to any relation as binding pointers specify
		public virtual Object? get_source()
		{
			if (data == null)
				return (null);
			if (data == SELF)
				return (this);
			bool redirect = false;
			// note that custom pointers can break the chain if they are set to point something 
			// else, otherwise redirection would not be possible as it would always fall on original
			Object? obj = redirect_to (ref redirect);
			if (redirect == true) {
				if (is_binding_pointer(obj) == true)
					return (((BindingPointer) obj).get_source());
				return (obj);
			}
			// if redirection was not there, follow the chain
			if (is_binding_pointer(data) == true)
				return (((BindingPointer) data).get_source());
			return (data);
		}

		protected virtual void handle_weak_ref (Object obj)
		{
			if (report_possible_binding_errors == true)
				stderr.printf ("Error? Last binding source reference is being dropped in WEAK mode!\n" +
				               "       This probably should never happen! This simply means weak source is handled by\n" +
				               "       weak contract binding. Set contract to STRONG mode unless there is specific reason\n" +
				               "       to handle it like this and dropping part is a feature\n");
			// check if data being disposed is real data. if data points to something else, data will stay the same
			if (obj == data) {
				data_disposed = true;
				data = null;
				data_disposed = false;
			}
		}

		private void handle_strict_ref()
		{
			data_disposed = true;
		}

		private void handle_store_weak_ref (Object obj)
		{
			unref();
		}

		private void sub_source_changed (BindingPointer pointer)
		{
			source_changed (this);
		}

		private void before_sub_source_change (BindingPointer pointer, bool is_same, Object? next)
		{
			before_source_change (this, is_same, next);
//			before_source_change (pointer, is_same, next);
		}

		private void data_dispatch_notify (Object obj, ParamSpec parm)
		{
			notify_property("data");
		}

		public void handle_data_changed (BindingPointer source, string data_change_cookie)
		{
			data_changed (this, data_change_cookie);
		}

		public void handle_connect_notifications (Object? obj)
		{
			connect_notifications (obj);
		}

		public void handle_disconnect_notifications (Object? obj)
		{
			disconnect_notifications (obj);
		}

		private void chain_pointer()
		{
			if (is_binding_pointer(data) == false)
				return;
			((BindingPointer) data).source_changed.connect (sub_source_changed);
			((BindingPointer) data).before_source_change.connect (before_sub_source_change);
			((BindingPointer) data).connect_notifications.connect (handle_connect_notifications);
			((BindingPointer) data).disconnect_notifications.connect (handle_disconnect_notifications);
			((BindingPointer) data).data_changed.connect (handle_data_changed);
			((BindingPointer) data).notify["data"].connect (data_dispatch_notify);
		}

		private void unchain_pointer()
		{
			if (is_binding_pointer(data) == false)
				return;
			((BindingPointer) data).source_changed.disconnect (sub_source_changed);
			((BindingPointer) data).before_source_change.disconnect (before_sub_source_change);
			((BindingPointer) data).connect_notifications.disconnect (handle_connect_notifications);
			((BindingPointer) data).disconnect_notifications.disconnect (handle_disconnect_notifications);
			((BindingPointer) data).data_changed.disconnect (handle_data_changed);
			((BindingPointer) data).notify["data"].disconnect (data_dispatch_notify);
		}

		public BindingPointer hold (BindingPointer pointer)
		{
			pointer.ref();
			pointer.weak_ref (pointer.handle_store_weak_ref);
			return (pointer);
		}

		public void release (BindingPointer pointer)
		{
			pointer.weak_unref (handle_store_weak_ref);
		}

		protected virtual bool reference_data()
		{
			if (data == null)
				return (false);
			data_disposed = false;
			if ((reference_type == BindingReferenceType.WEAK) || (reference_type == BindingReferenceType.DEFAULT))
				data.weak_ref (handle_weak_ref);
			else
				data.@ref();
			return (true);
		}

		protected virtual bool unreference_data()
		{
			if (data == null)
				return (false);
			if ((reference_type == BindingReferenceType.WEAK) || (reference_type == BindingReferenceType.DEFAULT))
				data.weak_unref (handle_weak_ref);
			else
				data.unref();
			data_disposed = false;
			return (true);
		}

		// Signal that emits notification data in pointer has changed. When needed, this signal should be 
		// emited either from outside code or from connections made in "connect-notifications". Later is
		// probably much better for retaining clean code
		//
		// The major useful part here is that contract is already binding pointer
		public signal void data_changed (BindingPointer source, string data_change_cookie);

		// Signal is called whenever binding pointer "get_source()" would start pointing to new valid location
		// and allows custom handling to control emission of custom notifications with "data-changed"
		// This signal is only emited when "binding-type" is MANUAL
		public signal void connect_notifications (Object? obj);

		// Signal is called when "get_source()" is just about to be starting pointing to something else in
		// order for custom binding pointer to be able to disconnect emission of custom "data-changed" 
		// notifications
		// This signal is only emited when "binding-type" is MANUAL
		public signal void disconnect_notifications (Object? obj);

		// Signal specifies "get_source()" will be pointing to something else after handling is over
		// While it seems like a duplication of "connect-notifications", it is not.
		// "connect-notifications" is only emited when "binding-type" is MANUAL and there are a lot of
		// cases when "connect-notifications" can retain stable notifications trough whole application 
		// life, while "before-source-change" will need to inform every interested part that "get_source()"
		// will now point to something new
		public signal void before_source_change (BindingPointer source, bool same_type, Object? next_source);

		// Signal is sent after "get_source()" points to new data. 
		public signal void source_changed (BindingPointer source);

		public BindingPointer (Object? data = null, BindingReferenceType reference_type = BindingReferenceType.WEAK, BindingPointerUpdateType update_type = BindingPointerUpdateType.PROPERTY)
		{
			_data = new StrictWeakReference<Object?> (null, handle_strict_ref);
			_reference_type = reference_type;
			_update_type = update_type;
			this.data = data;
		}
	}

	// Adds completely self-dependent functionality to be easily included in any class
	//
	// While set_data/get_data is slow, they only occur on adding/removing state objects, where there is
	// almost no use case binding contract could require more than 10 per contract where 10 is exaggerated.
	//
	// Once added to they are instantly taken over by direct signals and never rely on get_data/set_data 
	// for whole life time
	public interface IBindingStateObjects : Object
	{
		// these methods only practical use is to simplify code using them as it 
		// removes strain for application to keep the reference validity
		public void clean_state_objects()
		{
			GLib.Array<CustomBindingSourceState>? arr = get_data<GLib.Array<CustomBindingSourceState>> (BINDING_SOURCE_STATE_DATA);
			if (arr == null)
				return;
			while (arr.length > 0)	
				remove_state (arr.data[arr.length-1].name);
		}

		public CustomBindingSourceState add_state (CustomBindingSourceState state_object)
		{
			GLib.Array<CustomBindingSourceState>? arr = get_data<GLib.Array<CustomBindingSourceState>> (BINDING_SOURCE_STATE_DATA);
			if (arr == null) {
				arr = new GLib.Array<CustomBindingSourceState>();
				set_data<GLib.Array<CustomBindingSourceState>> (BINDING_SOURCE_STATE_DATA, arr);
			}
			for (int i=0; i<arr.length; i++)
				if (arr.data[i].name == state_object.name)
					return (arr.data[i]);
			arr.append_val (state_object);
			return (state_object);
		}

		public CustomBindingSourceState? get_state_object (string name)
		{
			GLib.Array<CustomBindingSourceState>? arr = get_data<GLib.Array<CustomBindingSourceState>> (BINDING_SOURCE_STATE_DATA);
			if (arr == null)
				return (null);
			for (int i=0; i<arr.length; i++)
				if (arr.data[i].name == name)
					return ((CustomBindingSourceState?) arr.data[i]);
			return (null);
		}

		public void remove_state (string name)
		{
			GLib.Array<CustomBindingSourceState>? arr = get_data<GLib.Array<CustomBindingSourceState>> (BINDING_SOURCE_STATE_DATA);
			if (arr == null)
				return;
			for (int i=0; i<arr.length; i++) {
				if (arr.data[i].name == name) {
					arr.data[i].disconnect_object();
					arr.remove_index (i);
					return;
				}
			}
		}
	}

	// Adds completely self-dependent functionality to be easily included in any class
	//
	// While set_data/get_data is slow, they only occur on adding/removing state objects, where there is
	// almost no use case binding contract could require more than 10 per contract where 10 is exaggerated.
	//
	// Once added to they are instantly taken over by direct signals and never rely on get_data/set_data 
	// for whole life time
	public interface IBindingValueObjects : Object
	{
		public void clean_source_values()
		{
			GLib.Array<CustomPropertyNotificationBindingSource>? arr = get_data<GLib.Array> (BINDING_SOURCE_VALUE_DATA);
			if (arr == null)
				return;
			while (arr.length > 0)
				remove_source_value (arr.data[arr.length-1].name);
		}

		public CustomPropertyNotificationBindingSource add_source_value (CustomPropertyNotificationBindingSource data_object)
		{
			GLib.Array<CustomPropertyNotificationBindingSource>? arr = get_data<GLib.Array<CustomPropertyNotificationBindingSource>> (BINDING_SOURCE_VALUE_DATA);
			if (arr == null) {
				arr = new GLib.Array<CustomPropertyNotificationBindingSource>();
				set_data<GLib.Array<CustomPropertyNotificationBindingSource>> (BINDING_SOURCE_VALUE_DATA, arr);
			}
			for (int i=0; i<arr.length; i++)
				if (arr.data[i].name == data_object.name)
					return (arr.data[i]);
			arr.append_val (data_object);
			return (data_object);
		}

		public CustomPropertyNotificationBindingSource? get_source_value (string name)
		{
			GLib.Array<CustomPropertyNotificationBindingSource>? arr = get_data<GLib.Array<CustomPropertyNotificationBindingSource>> (BINDING_SOURCE_VALUE_DATA);
			if (arr == null)
				return (null);
			for (int i=0; i<arr.length; i++)
				if (arr.data[i].name == name)
					return (arr.data[i]);
			return (null);
		}

		public void remove_source_value (string name)
		{
			GLib.Array<CustomPropertyNotificationBindingSource>? arr = get_data<GLib.Array<CustomPropertyNotificationBindingSource>> (BINDING_SOURCE_VALUE_DATA);
			if (arr == null)
				return;
			for (int i=0; i<arr.length; i++) {
				if (arr.data[i].name == name) {
					arr.data[i].disconnect_object();
					arr.remove_index (i);
					return;
				}
			}
		}
	}

	public class CustomPropertyNotificationBindingSource : Object
	{
		private bool _disconnected = false;
		public bool disconnected {
			get { return (_disconnected); }
		}

		public string name { get; set; }
		
		public virtual void disconnect_object()
		{
		}

		private string[]? connected_properties;
		private bool notify_connected = false;

		private WeakReference<BindingPointer?> _source;
		public BindingPointer source {
			get { return (_source.target); }
		}

		private void property_notification (GLib.ParamSpec paramspec)
		{
			properties_changed();
		}

		private void set_property_connection (bool active)
		{
			if ((notify_connected == active) || (connected_properties == null) || (source.get_source() == null))
				return;
			notify_connected = active;
			if (notify_connected == true) {
				if (connected_properties.length == 0)
					source.get_source().notify.connect (property_notification);
				else
					for (int i=0; i<connected_properties.length; i++)
						source.get_source().notify[connected_properties[i]].connect (property_notification);
			}
			else {
				if (connected_properties.length == 0)
					source.get_source().notify.disconnect (property_notification);
				else
					for (int i=0; i<connected_properties.length; i++)
						source.get_source().notify[connected_properties[i]].disconnect (property_notification);
			}
		}

		public signal void properties_changed();

		~CustomPropertyNotificationBindingSource()
		{
			if (disconnected == true)
				return;
			_disconnected = true;
			disconnect_object();
		}

		public CustomPropertyNotificationBindingSource (string name, BindingPointer source, string[]? connected_properties = null)
		{
			this.name = name;
			this.connected_properties = connected_properties;
			_source = new WeakReference<BindingPointer?>(source);
			source.before_source_change.connect ((src) => {
				set_property_connection (false);
			});
			source.source_changed.connect ((src) => {
				set_property_connection (true);
				properties_changed();
			});
			set_property_connection (true);
		}
	}

	public class CustomBindingSourceState : CustomPropertyNotificationBindingSource
	{
		private CustomBindingSourceStateFunc? _check_state = null;
		public CustomBindingSourceStateFunc? check_state {
			get { return (_check_state); }
			set {
				if (_check_state == value)
					return;
				_check_state = value;
				check_source_state(); 
			}
		}

		private bool _state = false;
		public bool state {
			get { return (_state); }
		}

		private void check_source_state()
		{
			bool new_state = false;
			if (_check_state != null)
				new_state = _check_state (source);
			if (new_state != state) {
				_state = new_state;
				notify_property("state");
			}
		}

		public CustomBindingSourceState (string name, BindingPointer source, CustomBindingSourceStateFunc state_check_method, string[]? connected_properties = null)
		{
			base (name, source, connected_properties);
			_check_state = state_check_method;
			properties_changed.connect (check_source_state);
			check_source_state();
		}
	}

	public class CustomBindingSourceValue : CustomPropertyNotificationBindingSource
	{
		// direct access of value instead of caching
		private bool _always_refresh = false;
		public bool always_refresh {
			get { return (_always_refresh); }
		}

		private GLib.Value? _data = null;
		public GLib.Value data {
			get {
				if (always_refresh == true)
					reset_data(); 
				if (_data == null)
					return (null_value);
				return (_data); 
			}
		}

		private GLib.Value _null_value;
		public GLib.Value null_value {
			get { return (_null_value); }
		}

		// IN CASE WHEN compare_method IS NULL 
		// property notify for data change is not called as this should be handled
		// from resolve_data delegate to avoid whole mess of innacuracy
		private CustomBindingSourceDataFunc<GLib.Value?>? _resolve_data = null;
		public CustomBindingSourceDataFunc<GLib.Value?>? resolve_data {
			get { return (_resolve_data); }
			set {
				if (_resolve_data == value)
					return;
				_resolve_data = value;
				reset_data(); 
			}
		}

		private CompareFunc<GLib.Value?>? _compare_func = null;
		public CompareFunc<GLib.Value?>? compare_func {
			get { return (_compare_func); }
		}

		private void reset_data()
		{
			GLib.Value? dt = null;
			if (_resolve_data != null)
				dt = resolve_data<GLib.Value> (source);
			if (_compare_func != null) {
				if ((_data == null) && (dt == null))
					return;
				if (((_data == null) || (dt == null)) || (compare_func<GLib.Value?>(dt, _data) != 0)) {
					_data = dt;
					notify_property ("data");
				}
			}
			else
				_data = dt;
		}

		public CustomBindingSourceValue (string name, BindingPointer source, CustomBindingSourceDataFunc<GLib.Value?> get_data_method, CompareFunc<GLib.Value?>? compare_method, GLib.Value null_value,
		                                 bool always_refresh = false, string[]? connected_properties = null)
		{
			base (name, source, connected_properties);
			_null_value = null_value;
			_always_refresh = always_refresh;
			_resolve_data = get_data_method;
			_compare_func = compare_method;
			properties_changed.connect (reset_data);
			reset_data();
		}
	}

	// in C rewrite this probably shouldn't be included. Only purpose of this being
	// here is to have more options for POC demo. This class might as well be reimplemented
	// in Vala at any time if needed 
	public class CustomBindingSourceData<T> : CustomPropertyNotificationBindingSource
	{
		// direct access of value instead of caching
		private bool _always_refresh = false;
		public bool always_refresh {
			get { return (_always_refresh); }
		}

		private T? _data = null;
		public T data {
			get {
				if (always_refresh == true)
					reset_data(); 
				if (_data == null)
					return (null_value);
				return (_data); 
			}
		}

		private T _null_value;
		public T null_value {
			get { return (_null_value); }
		}

		// IN CASE WHEN compare_method IS NULL 
		// property notify for data change is not called as this should be handled
		// from resolve_data delegate to avoid whole mess of innacuracy
		private CustomBindingSourceDataFunc<T>? _resolve_data = null;
		public CustomBindingSourceDataFunc<T>? resolve_data {
			get { return (_resolve_data); }
			set {
				if (_resolve_data == value)
					return;
				_resolve_data = value;
				reset_data(); 
			}
		}

		private CompareFunc<T>? _compare_func = null;
		public CompareFunc<T>? compare_func {
			get { return (_compare_func); }
		}

		private void reset_data()
		{
			T? dt = null;
			if (_resolve_data != null)
				dt = resolve_data<T> (source);
			if (_compare_func != null) {
				if ((_data == null) && (dt == null))
					return;
				if (((_data == null) || (dt == null)) || (compare_func<T>(dt, _data) != 0)) {
					_data = dt;
					notify_property ("data");
				}
			}
			else
				_data = dt;
		}

		public CustomBindingSourceData (string name, BindingPointer source, CustomBindingSourceDataFunc<T> get_data_method, CompareFunc<T>? compare_method, T null_value,
		                                bool always_refresh = false, string[]? connected_properties = null)
		{
			base (name, source, connected_properties);
			_null_value = null_value;
			_always_refresh = always_refresh;
			_resolve_data = get_data_method;
			_compare_func = compare_method;
			properties_changed.connect (reset_data);
			reset_data();
		}
	}

	public interface BindingInformationInterface : Object
	{
		public abstract bool is_valid { get; }
		public abstract void bind_connection();
		public abstract void unbind_connection();
	}

	public interface BindingGroup : Object
	{
		public abstract int length { get; }
		public abstract BindingInformationInterface get_item_at (int index);
	}

	// In rewrite this most probably shouldn't call GBinding. Instead functionality same as GBinding 
	// should be implemented, but with support for activation or manual transfer trigger
	public class BindingInformation : Object, BindingInformationInterface
	{
		private BindingInterface? binding = null;

		private WeakReference<BindingContract?> _contract;
		public BindingContract? contract {
			get { return (_contract.target); }
		}

		public bool can_bind {
			get { return (!((contract == null) || (contract.can_bind == false) || (target == null))); }
		}

		private bool? last_valid_state = null;
		public bool is_valid {
			get {
				if (last_valid_state == null)
					check_validity();
				return (last_valid_state);
			}
		}

		private string _source_property = "";
		public string source_property {
			get { return (_source_property); }
		}

		private WeakReference<Object?> _target;
		public Object? target {
			get { return (_target.target); }
		}

		private string _target_property = "";
		public string target_property {
			get { return (_target_property); }
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

		private SourceValidationFunc? _source_validation = null;
		public SourceValidationFunc? source_validation {
			get { return (_source_validation); }
		}

		public void remove()
		{
			if (contract != null)
				contract.unbind (this);
		}

		private void check_validity()
		{
			bool validity = true;
			if (can_bind == true) {
				GLib.Value val = GLib.Value(typeof(string));
				contract.get_source().get_property (source_property, ref val);
				if (check_if_valid_source_data(val) == false)
					validity = false;
			}
			else
				validity = false;
			if (last_valid_state != validity) {
				last_valid_state = validity;
				notify_property ("is-valid");
			}
		}

		private bool check_if_valid_source_data (Value? data)
		{
			if (binding == null)
				return (false);
			if (can_bind == false)
				return (false);
			if (_source_validation == null)
				return (true);
			return (source_validation (data));
		}

		private void check_source_property_validity (GLib.ParamSpec parm)
		{
			check_validity();
		}

		private void handle_before_target_source_change (BindingPointer target, bool is_same_type, Object? next_target)
		{
			unbind_connection();
		}

		private void handle_target_source_changed (BindingPointer target)
		{
			bind_connection();
		}

		public void bind_connection()
		{
			Object? tgt = target;
			if (is_binding_pointer(tgt) == true)
				tgt = ((BindingPointer) tgt).get_source();
			if (can_bind == false)
				return;
			if (binding != null)
				unbind_connection();
			if (tgt == null)
				return;
			// Check for property existance in both source and target 
			if (((ObjectClass) tgt.get_type().class_ref()).find_property(target_property) == null)
				if (PropertyAlias.get_instance(target_property).get_for(tgt.get_type()) == null)
					return;
			if (((ObjectClass) contract.get_source().get_type().class_ref()).find_property(source_property) == null)
				if (PropertyAlias.get_instance(source_property).get_for(contract.get_source().get_type()) == null)
					return;
			binding = contract.binder.bind (contract.get_source(), source_property, tgt, target_property, flags, transform_to, transform_from);
			check_validity();
			contract.get_source().notify[source_property].connect (check_source_property_validity);
		}

		public void unbind_connection()
		{
			if (contract.get_source() != null)
				contract.get_source().notify[source_property].disconnect (check_source_property_validity);
			if (binding != null)
				binding.unbind();
			binding = null;
		}

		// purpose of this is to have nice chaining API as keeping BindingInformation is not always necessary
		// note that this should only be called when you handle contract as whole and drop all bindings
		// whenever source changes
		// case and point example of that to happen is when source can be different types of data and you 
		// need to adapt editor in full   
		public BindingInformation bind (string source_property, Object target, string target_property, BindFlags flags = BindFlags.DEFAULT, 
		                                owned PropertyBindingTransformFunc? transform_to = null, owned PropertyBindingTransformFunc? transform_from = null, 
		                                owned SourceValidationFunc? source_validation = null)
		{
			return (contract.bind (source_property, target, target_property, flags, transform_to, transform_from, source_validation));
		}

		~BindingInformation()
		{
			if (is_binding_pointer(target) == true) {
				((BindingPointer) target).before_source_change.disconnect (handle_before_target_source_change);
				((BindingPointer) target).source_changed.disconnect (handle_target_source_changed);
			}
			_target = null;
		}
		
		internal BindingInformation (BindingContract owner_contract, string source_property, Object target, string target_property, 
		                             BindFlags flags = BindFlags.DEFAULT, owned PropertyBindingTransformFunc? transform_to = null, 
		                             owned PropertyBindingTransformFunc? transform_from = null, owned SourceValidationFunc? source_validation = null)
		{
			_contract = new WeakReference<BindingContract?>(owner_contract);
			_source_property = source_property;
			_target = new WeakReference<Object?>(target);
			_target_property = target_property;
			_flags = flags;
			_transform_to = transform_to;
			_transform_from = transform_from;
			_source_validation = source_validation;
			if (is_binding_pointer(target) == true) {
				((BindingPointer) target).before_source_change.connect (handle_before_target_source_change);
				((BindingPointer) target).source_changed.connect (handle_target_source_changed);
			}
			bind_connection();
		}
	}

	public class BindingPointerFromPropertyValue : BindingPointer
	{
		private bool data_disposed = true;
		private bool property_connected = false;
		private StrictWeakReference<Object?> _last = null;

		private string _data_property_name = "";
		public string data_property_name { 
			get { return (_data_property_name); }
		}

		private void handle_property_change (Object obj, ParamSpec prop)
		{
			_last = null;
			renew_data();
			if (_last.target != null)
				before_source_change (this, false, _last.target);
//			renew_data();
			if (_last.target != null)
				source_changed (this);
		}

		private void handle_before_source_change (BindingPointer pointer, bool is_same, Object? next)
		{
			if (_last.target != null) {
				if ((property_connected == true) || (data_disposed == false)) {
					get_source().notify[_data_property_name].disconnect (handle_property_change);
				}
				property_connected = false;
			}
			_last = null;
		}

		private void handle_source_changed (BindingPointer pointer)
		{
			_last = null;
			renew_data();
			if (_last.target != null) {
				if ((property_connected == true) || (data_disposed == false)) {
					_last.target.notify[_data_property_name].connect (handle_property_change);
					property_connected = false;
				}
			}
		}

		private void handle_strict_ref()
		{
			data_disposed = true;
			_last = null;
		}

		private void renew_data()
		{
			data_disposed = true;
			_last = new StrictWeakReference<Object?>(null);
			Object? obj;
			if (is_binding_pointer(data) == true)
				obj = ((BindingPointer) data).get_source();
			else
				obj = data;
			if (obj == null)
				return;
			ParamSpec? parm = ((ObjectClass) obj.get_type().class_ref()).find_property (_data_property_name);
			if (parm == null) {
				string? nn = PropertyAlias.get_instance(_data_property_name).get_for(obj.get_type());
				if (nn != null)
					parm = ((ObjectClass) obj.get_type().class_ref()).find_property (nn);
				if (parm == null)
					return;
			}
			if (parm.value_type.is_a(typeof(GLib.Object)) == false)
				return;
			GLib.Value val = GLib.Value(typeof(GLib.Object));
			obj.get_property (parm.name, ref val);
			Object oobj = val.get_object();
			data_disposed = false;
			_last = new StrictWeakReference<Object?>(oobj, handle_strict_ref);
		}

		protected override Object? redirect_to (ref bool redirect_in_play)
		{
			redirect_in_play = true;
			if (_last == null)
				renew_data();
			return (_last.target);
		}

		protected override bool reference_data()
		{
			bool res = base.reference_data();
			if (res == true) {
/*
				if ((reference_type == BindingReferenceType.WEAK) || (reference_type == BindingReferenceType.DEFAULT))
					data.weak_ref (handle_weak_ref);
				else
					data.@ref();
*/
			}
			return (true);
		}

		protected override bool unreference_data()
		{
			bool res = base.reference_data();
			if (res == true) {
			/*
				if ((reference_type == BindingReferenceType.WEAK) || (reference_type == BindingReferenceType.DEFAULT))
					data.weak_unref (handle_weak_ref);
				else
					data.unref();
					*/
			}
			data_disposed = false;
			return (true);
		}

		public BindingPointerFromPropertyValue (Object? data, string data_property_name, BindingReferenceType reference_type = BindingReferenceType.DEFAULT, BindingPointerUpdateType update_type = BindingPointerUpdateType.PROPERTY)
			requires (data_property_name != "")
		{
			base (data, reference_type, update_type);
			_data_property_name = data_property_name;
			before_source_change.connect (handle_before_source_change);
			source_changed.connect (handle_source_changed);
		}
	}

	// class used to store bindings in contracts. adds locking so
	// same binding can be added more than once and then removed 
	// only when lock drops to zero
	internal class BindingInformationReference
	{
		private int _lock_count = 1;
		public int lock_count {
			get { return (_lock_count); }
		}

		private BindingInformationInterface? _binding = null;
		public BindingInformationInterface? binding {
			get { return (_binding); }
		}

		public void lock()
		{
			_lock_count++;
		}

		public void unlock()
		{
			_lock_count--;
		}

		public void full_unlock()
		{
			_lock_count = 0;
		}

		public void reset()
		{
			_binding = null;
		}

		~BindingInformationReference()
		{
			_binding = null;
		}

		public BindingInformationReference (BindingInformationInterface binding)
		{
			_binding = binding;
		}
	}

	public class BindingContract : BindingPointer, IBindingStateObjects, IBindingValueObjects
	{
		private bool finalizing_in_progress = false;

		private GLib.Array<BindingInformationReference> _items = new GLib.Array<BindingInformationReference>();
		private WeakReference<Object?> last_source = new WeakReference<Object?>(null);

		public uint length {
			get { 
				if (_items == null)
					return (0);
				return (_items.length); 
			}
		}

		private bool _suspended = false;
		public bool suspended {
			get { return (_suspended == true); }
			set {
				if (_suspended == value)
					return;
				_suspended = value;
				if (can_bind == true)
					bind_contract();
				else
					disolve_contract(true);
			}
		}

		public bool can_bind {
			get { return ((_suspended == false) && (get_source() != null)); }
		}

		private bool _last_valid_state = false;
		public bool is_valid {
			get { return (_last_valid_state); }
		}

		private BindingPointer? _default_target = null;
		public Object? default_target {
			get { return (_default_target.data); }
			set {
				if (_default_target == null)
					_default_target = new BindingPointer (null, reference_type);
				if (default_target == value)
					return;
				_default_target.data = value;
			}
		}

		private Binder? _binder = null;
		public Binder? binder {
			owned get { 
				if (_binder == null)
					return (Binder.get_default());
				return (_binder); 
			}
			set { binder = value; }
		}

		private void disconnect_lifetime()
		{
			if (data == null)
				return;
			if (is_binding_pointer(data) == true) {
				sub_source_changed(this);

				before_source_change.disconnect (master_before_sub_source_change);
				((BindingPointer) data).source_changed.connect (sub_source_changed);
				((BindingPointer) data).before_source_change.connect (before_sub_source_change);
			}
			handle_is_valid (null);
		}

		private void sub_source_changed (BindingPointer src)
		{
			bind_contract(false);
			handle_is_valid (null);
		}

		private void before_sub_source_change (BindingPointer src, bool same_type, Object? next_source)
		{
			disolve_contract (false);//next_source == null);
			handle_is_valid (null);
		}

		private void master_before_sub_source_change (BindingPointer src, bool same_type, Object? next_source)
		{
			if (data == null)
				return;
		}

		protected override void handle_weak_ref(Object obj)
		{
			disolve_contract(get_source() == null);
			base.handle_weak_ref (obj);
		}

		private void connect_lifetime()
		{
			if (data == null)
				return;

			// connect to lifetime if this is a case for source chaining 
			if (is_binding_pointer(data) == true) {
				sub_source_changed(this);

				before_source_change.connect (master_before_sub_source_change);
			}
			handle_is_valid (null);
		}

		private void disolve_contract (bool emit_contract_change)
		{
			// no check here as it needs to be avoided in upper levels or before call
			for (int i=0; i<_items.data.length; i++)
				_items.data[i].binding.unbind_connection();
			if (emit_contract_change == true)
				contract_changed (this);
		}

		private void bind_contract(bool emit_contract_change = true)
		{
			if (can_bind == false)
				return;
			for (int i=0; i<_items.length; i++)
				_items.data[i].binding.bind_connection();
			if (emit_contract_change == true)
				contract_changed (this);
			handle_is_valid (null);
		}

		public BindingInformationInterface? get_item_at_index (int index)
		{
			if ((index < 0) || (index >= length))
				return (null);
			return (_items.data[index].binding);
		}

		private void handle_is_valid (ParamSpec? parm)
		{
			bool validity = true;
			if (get_source() != null)
				for (int i=0; i<_items.data.length; i++) {
					if (_items.data[i].binding.is_valid == false) {
						validity = false;
						break;
					}
				}
			else
				validity = false;
			if (validity != _last_valid_state) {
				_last_valid_state = validity;
				notify_property ("is-valid");
			}
		}

		public void bind_group (BindingGroup? group)
			requires (group != null)
		{
			for (int cnt = 0; cnt<group.length; cnt++)
				bind_information (group.get_item_at (cnt));
		}

		public void unbind_group (BindingGroup? group)
			requires (group != null)
		{
			for (int cnt = 0; cnt<group.length; cnt++)
				unbind (group.get_item_at (cnt));
		}

		public BindingInformationInterface? bind_information (BindingInformationInterface? info)
		{
			if (info == null)
				return (null);
			for (int cnt=0; cnt<_items.length; cnt++)
				if (_items.data[cnt].binding == info) {
					_items.data[cnt].lock();
					return (info);
				}
			_items.append_val (new BindingInformationReference (info));
			info.notify["is-valid"].connect (handle_is_valid);
			return (info);
		}

		public BindingInformation bind (string source_property, Object target, string target_property, BindFlags flags = BindFlags.DEFAULT, 
		                                owned PropertyBindingTransformFunc? transform_to = null, owned PropertyBindingTransformFunc? transform_from = null,
		                                owned SourceValidationFunc? source_validation = null)
			requires (source_property != "")
			requires (target_property != "")
		{
			return ((BindingInformation) bind_information (new BindingInformation (this, source_property, target, target_property, flags, transform_to, transform_from, source_validation)));
		}

		public BindingInformation bind_default (string source_property, string target_property, BindFlags flags = BindFlags.DEFAULT, 
		                                        owned PropertyBindingTransformFunc? transform_to = null, owned PropertyBindingTransformFunc? transform_from = null,
		                                        owned SourceValidationFunc? source_validation = null)
			requires (source_property != "")
			requires (target_property != "")
		{
			return ((BindingInformation) bind_information (new BindingInformation (this, source_property, _default_target, target_property, flags, transform_to, transform_from, source_validation)));
		}

		public void unbind (BindingInformationInterface information, bool all_references = false)
		{
			for (int i=0; i<length; i++) {
				if (_items.data[i].binding == information) {
					if (all_references == false) {
						if (_items.data[i].lock_count > 1)
							_items.data[i].unlock();
					}
					else
						_items.data[i].full_unlock();
					information.notify["is-valid"].disconnect (handle_is_valid);
					information.unbind_connection();
//					_items.data[i].reset();
					_items.remove_index (i);
					break;
				}
			}
		}

		public void unbind_all()
		{
			while (length > 0)
				unbind(get_item_at_index((int)length-1));
		}

		public signal void contract_changed (BindingContract contract);

		public signal void bindings_changed (BindingContract contract, ContractChangeType change_type, BindingInformation binding);

		protected virtual void disconnect_contract()
		{
			if (finalizing_in_progress == true)
				return;
			finalizing_in_progress = true;
			clean_state_objects();
			clean_source_values();
			unbind_all();
			data = null;
		}

		~BindingContract()
		{
			if (finalizing_in_progress == true)
				return;
			disconnect_contract();
		}

		public BindingContract.add_to_manager (ContractStorage contract_manager, string name, Object? data = null, BindingReferenceType reference_type = BindingReferenceType.WEAK, BindingPointerUpdateType update_type = BindingPointerUpdateType.PROPERTY)
		{
			this (data, reference_type, update_type);
			contract_manager.add (name, this);
		}

		public BindingContract.add_to_default_manager (string name, Object? data = null, BindingReferenceType reference_type = BindingReferenceType.WEAK, BindingPointerUpdateType update_type = BindingPointerUpdateType.PROPERTY)
		{
			this.add_to_manager (ContractStorage.get_default(), name, data, reference_type, update_type);
		}

		public BindingContract (Object? data = null, BindingReferenceType reference_type = BindingReferenceType.WEAK, BindingPointerUpdateType update_type = BindingPointerUpdateType.PROPERTY)
		{
			base (null, reference_type, update_type);
			before_source_change.connect((binding, is_same, next) => {
				if (get_source() != null) {
					disolve_contract (next == null);
					disconnect_lifetime();
				}
			});
			contract_changed.connect ((src) => { 
				if (last_source.target == src.get_source())
					return;
				last_source = new WeakReference<Object?>(src.get_source());
			});
			source_changed.connect ((binding) => {
				if (get_source() != null) {
					connect_lifetime();
					bind_contract();
				}
			});
			this.data = data;
			// no binding here yet, so nothing else is required
		}
	}

	public class BindingSuspensionGroup : Object
	{
		private static int counter = 1;

		private int id;

		private bool _suspended = false;
		public bool suspended {
			get { return (_suspended); }
			set { 
				if (_suspended == value)
					return;
				_suspended = value; 
			}
		}

		public void add (BindingContract? contract)
		{
			if (contract == null)
				return;
			StrictWeakReference<PropertyBinding?> prop = contract.get_data<StrictWeakReference<PropertyBinding?>>("suspend-group-%i".printf(id));
			if ((prop != null) && (prop.target != null))
				return;
			PropertyBinding nprop = PropertyBinding.bind (this, "suspended", contract, "suspended", BindFlags.SYNC_CREATE);
			contract.set_data<StrictWeakReference<PropertyBinding?>> ("suspend-group-%i".printf(id), new StrictWeakReference<PropertyBinding?>(nprop));
		}

		public void remove (BindingContract? contract)
		{
			StrictWeakReference<PropertyBinding?> prop = contract.get_data<StrictWeakReference<PropertyBinding?>> ("suspend-group-%i".printf(id));
			if ((prop != null) && (prop.target != null)) {
				contract.set_data<StrictWeakReference<PropertyBinding?>> ("suspend-group-%i".printf(id), new StrictWeakReference<PropertyBinding?> (null));
				prop.target.unbind();
			}
		}

		public BindingSuspensionGroup()
		{
			id = counter;
			counter++;
		}
	}

	public class PointerArray : MasterSlaveArray<string, string, WeakReference<BindingPointer>>
	{
	}

	private static void add_ptr_storage (string s, PointerArray list)
	{
		KeyValueArray<string, WeakReference<BindingPointer>> sub_list = new KeyValueArray<string, WeakReference<BindingPointer>>();
		PointerStorage storage = PointerStorage.get_storage (s);
		storage.foreach_registration ((t, p) => {
			sub_list.add (new KeyValuePair<string, WeakReference<BindingPointer>> (t, new WeakReference<BindingPointer>(p)));
		});
		storage.added.connect ((t, p) => {
			sub_list.add (new KeyValuePair<string, WeakReference<BindingPointer>> (t, new WeakReference<BindingPointer>(p)));
		});
		storage.removed.connect ((t, p) => {
			for (int i=0; i<sub_list.length; i++) {
				if (p == sub_list.data[i].val.target) {
					sub_list.remove_at_index(i);
					return;
				}
			}
		});
		KeyValuePair<string, KeyValueArray<string, WeakReference<BindingPointer>>> pair = 
			new KeyValuePair<string, KeyValueArray<string, WeakReference<BindingPointer>>>(s, sub_list);
		list.add (pair);
	}

	public static PointerArray track_pointer_storage()
	{
		PointerArray list = new PointerArray();
		PointerStorage.foreach_storage ((s) => {
			add_ptr_storage (s, list);
		});
		PointerStorage.StorageSignal.get_instance().added_storage.connect ((s) => {
			add_ptr_storage (s, list);
		});
		return (list);
	}

	// storage for pointers in order to have guaranteed reference when
	// there is no need for local variable or to have them globally 
	// accessible by name
	public class PointerStorage : Object
	{
		internal class StorageSignal
		{
			private static StorageSignal? _instance = null;
			public static StorageSignal get_instance()
			{
				if (_instance == null)
					_instance = new StorageSignal();
				return (_instance);
			}

			public signal void added_storage (string storage_name);
		}

		internal static void foreach_storage (Func<string> method)
		{
			if (_storages != null)
				_storages.for_each ((s,p) => {
					method(s);
				});
		}

		internal void foreach_registration (HFunc<string, BindingContract> method)
		{
			if (_objects != null)
				_objects.for_each (method);
		}

		private static HashTable<string, PointerStorage>? _storages = null;
		private HashTable<string, BindingPointer>? _objects = null;

		private static void _check()
		{
			if (_storages == null)
				_storages = new HashTable<string, PointerStorage> (str_hash, str_equal);
		}

		public static PointerStorage get_default()
		{
			return (get_storage (__DEFAULT__));
		}

		public static PointerStorage? get_storage (string name)
		{
			_check();
			PointerStorage? store = _storages.get (name);
			if (store == null) {
				store = new PointerStorage();
				_storages.insert (name, store);
				StorageSignal.get_instance().added_storage (name);
			}
			return (store);
		}

		public BindingPointer? find (string name)
		{
			if (_objects == null)
				return (null);
			return (_objects.get (name));
		}

		public BindingPointer? add (string name, BindingPointer? obj)
		{
			if (obj == null) {
				GLib.warning ("Trying to add [null] as stored pointer \"%s\"!".printf(name));
				return (null);
			}
			if (find(name) != null) {
				GLib.critical ("Duplicate stored pointer \"%s\"!".printf(name));
				return (null);
			}
			if (_objects == null)
				_objects = new HashTable<string, BindingPointer> (str_hash, str_equal);
			_objects.insert (name, obj);
			added (name, obj);
			return (obj);
		}

		public void remove (string name)
		{
			BindingPointer obj = find (name);
			if (obj == null)
				return;
			_objects.remove (name);
			removed (name, obj);
		}

		public signal void added (string name, BindingPointer obj);

		public signal void removed (string name, BindingPointer obj);

		public PointerStorage()
		{
			_objects = new HashTable<string, BindingPointer> (str_hash, str_equal);
		}
	}

	public class ContractArray : MasterSlaveArray<string, string, WeakReference<BindingContract>>
	{
	}

	private static void add_storage (string s, ContractArray list)
	{
		KeyValueArray<string, WeakReference<BindingContract>> sub_list = new KeyValueArray<string, WeakReference<BindingContract>>();
		ContractStorage storage = ContractStorage.get_storage (s);
		storage.foreach_registration ((t, p) => {
			sub_list.add (new KeyValuePair<string, WeakReference<BindingContract>> (t, new WeakReference<BindingContract>(p)));
		});
		storage.added.connect ((t, p) => {
			sub_list.add (new KeyValuePair<string, WeakReference<BindingContract>> (t, new WeakReference<BindingContract>(p)));
		});
		storage.removed.connect ((t, p) => {
			for (int i=0; i<sub_list.length; i++) {
				if (p == sub_list.data[i].val.target) {
					sub_list.remove_at_index(i);
					return;
				}
			}
		});
		KeyValuePair<string, KeyValueArray<string, WeakReference<BindingContract>>> pair = 
			new KeyValuePair<string, KeyValueArray<string, WeakReference<BindingContract>>>(s, sub_list);
		list.add (pair);
	}

	public static ContractArray track_contract_storage()
	{
		ContractArray list = new ContractArray();
		ContractStorage.foreach_storage ((s) => {
			add_storage (s, list);
		});
		ContractStorage.StorageSignal.get_instance().added_storage.connect ((s) => {
			add_storage (s, list);
		});
		return (list);
	}

	// storage for contracts in order to have guaranteed reference when
	// there is no need for local variable or to have them globally 
	// accessible by name
	public class ContractStorage : Object
	{
		internal class StorageSignal
		{
			private static StorageSignal? _instance = null;
			public static StorageSignal get_instance()
			{
				if (_instance == null)
					_instance = new StorageSignal();
				return (_instance);
			}

			public signal void added_storage (string storage_name);
		}

		internal static void foreach_storage (Func<string> method)
		{
			if (_storages != null)
				_storages.for_each ((s,p) => {
					method(s);
				});
		}

		internal void foreach_registration (HFunc<string, BindingContract> method)
		{
			if (_objects != null)
				_objects.for_each (method);
		}

		private static HashTable<string, ContractStorage>? _storages = null;
		private HashTable<string, BindingContract>? _objects = null;

		private static void _check()
		{
			if (_storages == null)
				_storages = new HashTable<string, ContractStorage> (str_hash, str_equal);
		}

		public static ContractStorage get_default()
		{
			return (get_storage (__DEFAULT__));
		}

		public static ContractStorage? get_storage (string name)
		{
			_check();
			ContractStorage? store = _storages.get (name);
			if (store == null) {
				store = new ContractStorage();
				_storages.insert (name, store);
				StorageSignal.get_instance().added_storage (name);
			}
			return (store);
		}

		public BindingContract? find (string name)
		{
			if (_objects == null)
				return (null);
			return (_objects.get (name));
		}

		public BindingContract? add (string name, BindingContract? obj)
		{
			if (obj == null) {
				GLib.warning ("Trying to add [null] as stored contract \"%s\"!".printf(name));
				return (null);
			}
			if (find(name) != null) {
				GLib.critical ("Duplicate stored contract \"%s\"!".printf(name));
				return (null);
			}
			if (_objects == null)
				_objects = new HashTable<string, BindingContract> (str_hash, str_equal);
			_objects.insert (name, obj);
			added (name, obj);
			return (obj);
		}

		public void remove (string name)
		{
			BindingContract obj = find (name);
			if (obj == null)
				return;
			_objects.remove (name);
			removed (name, obj);
		}

		public signal void added (string name, BindingContract obj);

		public signal void removed (string name, BindingContract obj);

		public ContractStorage()
		{
			_objects = new HashTable<string, BindingContract> (str_hash, str_equal);
		}
	}
}
