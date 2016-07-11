/*
 *
 * Databinding POC implementation in vala, later to be rewriten in C. Vala
 * is chosen for simple reason, I'm far more familiar with it and that
 * makes it much faster to prototype the end case scenario.
 *
 * TODO
 *
 * - Better and more complex demo that touches functionality somewhat seriously
 *   as current one more or less only does basic features
 *
 * - BindingSubContract or BindingPointerRedirection. Both are already done, but
 *   I am in process of testing which is more suitable. Main purpose they serve
 *   is having predictable source which is specified as sub-property from source
 *   which allows real chaining of whole databinding pipeline as you can build
 *   binding tree and have it handled as such. The reason why it is not included
 *   yet is because I want it to be flexible and extensible beyond simple 
 *   sub-property 
 * 
 * - Handling of activity and suspended in BindingInformation to avoid rebinding
 *   when it is not necessary. Only signal that needs to be connected for that
 *   is property notify for that is "can-bind" 
 *
 * What is handled?
 *
 * Beside the obvious as having single place to rebind same widgets to new
 * source object this also handles most corner case scenarios that show up once
 * you really dig into databinding application design
 *
 * - Control over who is keeping objects alive. BindingContract by default uses
 *   BindingReferenceType.WEAK which means that it is up to application to keep
 *   objects alive and in this case not single reference is installed. For
 *   cases where one needs to bind to weak objects BindingContract can be
 *   created with BindingReferenceType.TOGGLE which causes BindingContract to
 *   install toggle reference on source object which keeps it alive until either
 *   contract is destroyed or contract changes its binding source
 *
 * - Temporary contract suspending where contract disbands all its bindings to
 *   widgets until suspending is out of effect
 *
 * - Source validation tracking with BindingContract.is_valid where each added
 *   binding can specify its own case for its value validity and then adjust
 *   BindingContract.is_valid to represent cumulative state of that source
 *   object so application only needs to bind to that. Note that validation is
 *   based on "per-property" specifications on contract, not global. There is
 *   a high possibility that is_valid requirements are not the same for all
 *   contracts that connect to same object with same conditions. Global check
 *   is simply not needed as it is much better to use custom state object for
 *   that purpose. Making it available on contract would just clutter API, while
 *   "per-property" also just makes sense when it is considered bindings can be
 *   added/removed on the fly and at the same time always keep perfect condition
 *
 *   Usage example:
 *   binding Apply button "sensitive" to contract for whole lifetime of window 
 *   no matter how source object changes. As such it is just normal to simply 
 *   use Object.bind_property without slightest care. 
 *
 * - Complete required notification mechanism for creation of "rebuild-per-case"
 *   scenario as when source changes first one being dispatched is 
 *   "before_source_change" which provides type equality of current and next
 *   source as well as reference for next source. This signal is followed by
 *   "source_changed" which means contract at this point already points to 
 *   new source object. The fact that application can be aware of next type
 *   makes it easy to either drop/rebuild or just leave the widgets and bindings
 *   without any unnecesary flickering or strain. Contract it self also provides
 *   "contract-changed" which is triggered when bindings are added/removed to
 *   the contract
 *
 *   Usage example:
 *   Property editor like functionality where whole contents and widgets get
 *   replaced by contents that are related to new source object. While rebuild
 *   per case needs similar interaction as without data binding (drop
 *   widgets/create widgets) case for this is simple. Application can take
 *   consistent approach no matter what and there are reliable notifications it
 *   can rely on  
 *
 * - Availability of chaining contracts as source object where object being
 *   bound to is not contract, but rather source object it points to or in
 *   case of multiple chaining... source of last link in the chain. This it
 *   self will come even more in play with BindingSubContract (WIP).
 *   BindingSubContract will serve as redirection to particular data inside
 *   source object and it allows application to design whole databinding 
 *   pipeline as predictable plan as well as makes it possible to integrate
 *   it in Glade or similar application that is designed to plan data binding
 *   pipeline across the application
 *
 * - Availability of using manager objects to handle/group contracts by name so
 *   application can avoid tracking references. This guarantees that contract
 *   will always have minimal reference count which will be dropped as soon
 *   as contract is removed
 *
 * - This said, Object.bind_property becomes really functional when application
 *   follows correct design path. Using contracts where data changes and using
 *   bind_property where it doesn't.
 *
 *   Usage example:
 *   If you bind_model to list_box data object will be fixed. In this case it
 *   is much more appropriate to use bind_property when creating widgets trough
 *   model as it will be much more efficient than applying contract for each
 *   item
 *
 * - Each contract has default_target as well as custom targets per binding.
 *   The distinction is in what job binding contract will entail. There are
 *   two kinds of bindings that contract can offer. One is binding with GUI,
 *   second is creating contract between two objects and multiple properties.
 *   In both cases source is the same, while target won't be. In case of GUI
 *   most probably there will be different widgets as target objects, while
 *   in object<>object contract, both will be kept the same. In second case
 *   it is much more beneficial if target can have same single point of handling
 *   as source does.
 * 
 *   This is why BindingContract offers bind(...) and bind_default(...).
 *   bind(...) offers specification of custom target per binding, while
 *   bind_default(...) always points to default target which is stored as
 *   IBindingPointer and as such contains all the messaging requirements to
 *   automatically rebind to correct target that can be set at anytime with
 *   default_target property in BindingContract.
 *
 *   This design offers having simplified complex pipeline with least amount
 *   of contracts. Note that specifiying same target as default_target with
 *   bind(...) does not result same as calling bind_default(...) because that
 *   would remove ability to refer to one object as stable and moving target
 *   per need.
 * 
 *   NOTE! default_target is just convenience over creating
 *   ContractedBindingPointer and then setting it as target in all bind calls
 *   made per contract. Only difference is that application code will be much
 *   less readable
 *
 * NOTE! Up from here is handling of corner scenarios that always prove to be
 * the most annoying missing part for real usage. Main problem is that they only
 * become obvious when one has done data binding extensively in real world use
 * and had a serious thought about the problem
 *
 * Availability of state/value objects on binding source
 * =====================================================
 *
 * Main case for both is having stable fixed points of connection to binding
 * sources reflecting changes in order to simplify binding for stable parts
 * of GUI/application 
 *
 * - State objects are simple case of bool value where value represents state
 *   of specified condition per binding source. State is not only reflected when
 *   source changes, it can also specify which property notifications to connect
 *   to in order to provide accurate state. In this case Object.bind_property
 *   can be reliably used to have it as fixed and stable point of application
 *
 *   Usage example:
 *   Much like previously described validation with apply, this enables imposing
 *   custom conditions like being able to set visible/sensitive to certain
 *   widgets when Person is male or female or something similar.
 *
 * - Value objects are much like state objects with 2 differences. One is that
 *   they can represent any value type which comes with a little more complexity
 *   as in order to know how to check if value has changed application must
 *   specify CompareFunc or handle notification internally in value assignment.
 *   Another difference is that they allow for live resoving without caching of
 *   value which effectively removes the need to specify property change
 *   notifications value depends on
 *
 * NOTE! While state and value objects are very similar, it still makes sense
 * to differentiate between them as setting state has much simpler API and more
 * fixed requirements than custom value. One could as well always just create
 * value objects <bool> and treat them as such, only differnce is simplicity and
 * readability of code in application.
 *
 *
 *
 * *** just personal thought ***
 * Only real bummer in gtk when considered with databinding is that it doesn't
 * have either type attributes or something simple as
 *
 * virtual string get_value_property_name ()
 * {
 *     // default return when there is no such thing could simply be ""
 *     return ("label");
 * }
 *
 * on GObject or at least GtkWidget.
 *
 * This would be very efficient way to create autobinding templates (or knowing
 * when it is not possible with value being returned as "") and could really
 * advance the design of how laying out databinding plan is done. One of the
 * problems is that each widget has its own default value property such as
 * GtkLabel->"label", GtkEntry->"text"... which is not possible to know unless
 * you handle it per widget type case
 *
 * This is all in one file for the moment only because it is simpler to hack on
 * it this way. Normally, this would be separated.
 *
 */

namespace Gtk.Fx
{
	private const string BINDING_SOURCE_STATE_DATA = "binding-source-state-data";
	private const string BINDING_SOURCE_VALUE_DATA = "binding-source-value-data";
	
	public delegate bool SourceValidationFunc (Value? source_value);
	public delegate bool CustomBindingSourceStateFunc (IBindingPointer? source);
	public delegate T CustomBindingSourceDataFunc<T> (IBindingPointer? source_data);

	public const string[] ALL_PROPERTIES = {};

	public static bool report_possible_errors = false;
	
	public enum BindingReferenceType
	{
		WEAK,
		TOGGLE
	}

	public static bool is_binding_pointer (Object? obj)
	{
		if (obj == null)
			return (false);
		return (obj.get_type().is_a(typeof(IBindingPointer)) == true);
	}

	private static bool is_same_type (Object? obj1, Object? obj2)
	{
		if (obj1 == obj2)
			return (true);
		if ((obj1 == null) || (obj2 == null))
			return (false);
		return (obj1.get_type().is_a(obj2.get_type()));
	}

	public interface IBindingPointer : Object
	{
		public abstract Object? data { get; set; }

		public Object? get_source()
		{
			if (data == null)
				return (null);
			if (is_binding_pointer(data) == true)
				return (((IBindingPointer) data).get_source());
			return (data);
		}

		public signal void before_source_change (IBindingPointer source, bool same_type, Object? next_source);

		public signal void source_changed (IBindingPointer source);
	}

	public interface IBindingSource : Object
	{
		// these methods only practical use is to simplify code using them as it 
		// removes strain for application to keep the reference validity
		public void clean_state_objects()
		{
			GLib.Array<CustomBindingSourceState>? arr = get_data<GLib.Array<CustomBindingSourceState>> (BINDING_SOURCE_STATE_DATA);
			if (arr == null)
				return;
			while (arr.length > 0)	
				remove_state (arr.data[0].name);
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

		public void clean_source_values()
		{
			GLib.Array<CustomPropertyNotificationBindingSource>? arr = get_data<GLib.Array> (BINDING_SOURCE_VALUE_DATA);
			if (arr == null)
				return;
			while (arr.length > 0)
				remove_source_value (arr.data[0].name);
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

		private WeakReference<IBindingPointer?> _source;
		public IBindingPointer source {
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

		public CustomPropertyNotificationBindingSource (string name, IBindingPointer source, string[]? connected_properties = null)
		{
			this.name = name;
			this.connected_properties = connected_properties;
			_source = new WeakReference<IBindingPointer?>(source);
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

		public CustomBindingSourceState (string name, IBindingPointer source, CustomBindingSourceStateFunc state_check_method, string[]? connected_properties = null)
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

		public CustomBindingSourceValue (string name, IBindingPointer source, CustomBindingSourceDataFunc<GLib.Value?> get_data_method, CompareFunc<GLib.Value?>? compare_method, GLib.Value null_value,
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

		public CustomBindingSourceData (string name, IBindingPointer source, CustomBindingSourceDataFunc<T> get_data_method, CompareFunc<T>? compare_method, T null_value,
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

	public class BindingInformation : Object
	{
		private GLib.Binding? binding = null;

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

		private BindingFlags _flags = GLib.BindingFlags.DEFAULT;
		public BindingFlags flags {
			get { return (_flags); }
		}

		private BindingTransformFunc? _transform_to = null;
		public BindingTransformFunc? transform_to {
			get { return (_transform_to); }
		}

		private BindingTransformFunc? _transform_from = null;
		public BindingTransformFunc? transform_from {
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

		private void handle_before_target_source_change (IBindingPointer target, bool is_same_type, Object? next_target)
		{
			unbind_connection();
		}

		private void handle_target_source_changed (IBindingPointer target)
		{
			bind_connection();
		}

		internal void bind_connection()
		{
			if (can_bind == false)
				return;
			if (binding != null)
				unbind_connection();
			Object? tgt = target;
			if (is_binding_pointer(tgt) == true)
				tgt = ((IBindingPointer) tgt).get_source();
			if (tgt == null)
				return;
			// Check for property existance in both source and target 
			if (((ObjectClass) tgt.get_type().class_ref()).find_property(target_property) == null)
				return;
			if (((ObjectClass) contract.get_source().get_type().class_ref()).find_property(source_property) == null)
				return;
			binding = contract.get_source().bind_property (source_property, tgt, target_property, flags, transform_to, transform_from);
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
		public BindingInformation bind (string source_property, Object target, string target_property, BindingFlags flags = GLib.BindingFlags.DEFAULT, 
		                                owned BindingTransformFunc? transform_to = null, owned BindingTransformFunc? transform_from = null, 
		                                owned SourceValidationFunc? source_validation = null)
		{
			return (contract.bind (source_property, target, target_property, flags, transform_to, transform_from, source_validation));
		}

		~BindingInformation()
		{
			if (is_binding_pointer(target) == true) {
				((IBindingPointer) target).before_source_change.disconnect (handle_before_target_source_change);
				((IBindingPointer) target).source_changed.disconnect (handle_target_source_changed);
			}
			_target = null;
		}
		
		internal BindingInformation (BindingContract owner_contract, string source_property, Object target, string target_property, 
		                             BindingFlags flags = GLib.BindingFlags.DEFAULT, owned BindingTransformFunc? transform_to = null, 
		                             owned BindingTransformFunc? transform_from = null, owned SourceValidationFunc? source_validation = null)
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
				((IBindingPointer) target).before_source_change.connect (handle_before_target_source_change);
				((IBindingPointer) target).source_changed.connect (handle_target_source_changed);
			}
			bind_connection();
		}
	}

	public class ContractedBindingPointer : Object, IBindingPointer
	{
		private bool finalizing_in_progress = false;
		
		private WeakReference<Object?> _data = new WeakReference<Object?> (null);
		public Object? data { 
			get { return (_data.target); }
			set {
				if (data == value)
					return;
				before_source_change (this, is_same_type(data, value), value);
				if (data != null)
					unreference_data();
				_data = new WeakReference<Object?> (value);
				if (data != null)
					reference_data();
				source_changed (this);
			}
		}

		// null value means binding pointer takes value of its contract
		private BindingReferenceType? _reference_type = null;
		public BindingReferenceType reference_type {
			get {
				if (_reference_type == null)
					return (contract.reference_type); 
				return (_reference_type); 
			}
		}

		private WeakReference<BindingContract?> _contract;
		public BindingContract? contract {
			get { return (_contract.target); }
		}

		private void handle_toggle_ref (Object object, bool is_last_ref) 
		{
			// whole purpose of toggle ref is keeping source alive when it is weak
			// might as well completely ignore whole thing and let nature take its
			// course when contract will remove toggle by either changing source
			// or destroying it self. at that point toggle will be removed and
			// object will terminate on ref_count=0
		}

		private void handle_weak_ref (Object obj)
		{
			if (report_possible_errors == true)
				stderr.printf ("Error? Last binding source reference is being dropped in WEAK mode!\n" +
				               "       This probably should never happen! This simply means weak source is handled by\n" +
				               "       weak contract binding. Set contract to TOGGLE mode unless there is specific reason\n" +
				               "       to handle it like this\n");
			data = null;
		}

		protected virtual void reference_data()
		{
			if (reference_type == BindingReferenceType.WEAK)
				data.weak_ref (handle_weak_ref);
			else
				data.add_toggle_ref (handle_toggle_ref);
		}

		protected virtual void unreference_data()
		{
			if (reference_type == BindingReferenceType.WEAK)
				data.weak_unref (handle_weak_ref);
			else
				data.remove_toggle_ref (handle_toggle_ref);
		}

		private void handle_self_toggle_ref (Object obj, bool is_last)
		{
			finalizing_in_progress = true;
			data = null;
			remove_toggle_ref (handle_self_toggle_ref);
		}

		public ContractedBindingPointer (BindingContract contract, Object? data, BindingReferenceType? reference_type = null)
		{
			_reference_type = reference_type;
			_contract = new WeakReference<BindingContract> (contract);
			this.data = data;
			add_toggle_ref (handle_self_toggle_ref);
		}
	}

	public class BindingContract : Object, IBindingPointer, IBindingSource
	{
		private bool finalizing_in_progress = false;

		private bool toggle_set = false;
		private GLib.Array<BindingInformation> _items = new GLib.Array<BindingInformation>();
		private WeakReference<Object?> last_source = new WeakReference<Object?>(null);

		public uint length {
			get { return (_items.length); }
		}

		private BindingReferenceType _reference_type = BindingReferenceType.WEAK;
		public BindingReferenceType reference_type {
			get { return (_reference_type); }
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

		private WeakReference<Object?> _data = new WeakReference<Object?>(null);
		public Object? data {
			get { return (_data.target); }
			set { 
				if (data == value)
					return;
				if (data != null) {
					disolve_contract (value == null);
					disconnect_lifetime();
				}
				before_source_change (this, is_same_type(value, data), value);
				_data = new WeakReference<Object?>(value); 
				if (data != null) {
					connect_lifetime();
					bind_contract();
				}
				source_changed(this);
			}
		}

		private ContractedBindingPointer _default_target;
		public Object? default_target {
			get { return (_default_target.data); }
			set {
				if (default_target == value)
					return;
				_default_target.data = value;
			}
		}

		private void disconnect_lifetime()
		{
			if (data == null)
				return;
			if (get_source() != data) {
				stdout.printf ("disconnecting from something else\n");
				sub_source_changed(this);

				stdout.printf ("before messages\n");
				before_source_change.disconnect (master_before_sub_source_change);
				((IBindingPointer) data).source_changed.connect (sub_source_changed);
				((IBindingPointer) data).before_source_change.connect (before_sub_source_change);
			}

			if ((data != null) && (toggle_set == true))
				if (reference_type == BindingReferenceType.WEAK)
					data.weak_unref (handle_weak_ref);
				else
					data.remove_toggle_ref (handle_toggle_ref);
			toggle_set = false;
		}

		private void sub_source_changed (IBindingPointer src)
		{
			source_changed (this);
			bind_contract();
		}
		
		private void before_sub_source_change (IBindingPointer src, bool same_type, Object? next_source)
		{
			disolve_contract (next_source == null);
			before_source_change (this, same_type, next_source);
		}

		private void master_before_sub_source_change (IBindingPointer src, bool same_type, Object? next_source)
		{
			if (data == null)
				return;
		}

		private void handle_toggle_ref (Object object, bool is_last_ref) 
		{
			// whole purpose of toggle ref is keeping source alive when it is weak
			// might as well completely ignore whole thing and let nature take its
			// course when contract will remove toggle by either changing source
			// or destroying it self. at that point toggle will be removed and
			// object will terminate on ref_count=0
		}

		private void handle_weak_ref(Object obj)
		{
			if (report_possible_errors == true)
				stderr.printf ("Error? Last binding source reference is being dropped in WEAK mode!\n" +
				               "       This probably should never happen! This simply means weak source is handled by\n" +
				               "       weak contract binding. Set contract to TOGGLE mode unless there is specific reason\n" +
				               "       to handle it like this\n");
			disolve_contract(get_source() == null);
			if (get_source() == data)
				data = null;
			source_changed (this);
		}

		private void connect_lifetime()
		{
			if (data == null)
				return;

			// connect to lifetime if this is a case for source chaining 
			if (get_source() != data) {
				sub_source_changed(this);

				before_source_change.connect (master_before_sub_source_change);
				((IBindingPointer) data).source_changed.connect (sub_source_changed);
				((IBindingPointer) data).before_source_change.connect (before_sub_source_change);
			}

			if (toggle_set == false) {
				toggle_set = true;
				if (reference_type == BindingReferenceType.WEAK)
					data.weak_ref (handle_weak_ref);
				else
					data.add_toggle_ref (handle_toggle_ref);
			}
		}

		private void disolve_contract (bool emit_contract_change)
		{
			// no check here as it needs to be avoided in upper levels or before call
			for (int i=0; i<_items.data.length; i++)
				_items.data[i].unbind_connection();
			if (emit_contract_change == true)
				contract_changed (this);
		}

		private void bind_contract()
		{
			if (can_bind == false)
				return;
			for (int i=0; i<_items.length; i++)
				_items.data[i].bind_connection();
			contract_changed (this);
		}

		public BindingInformation? get_item_at_index (int index)
		{
			if ((index < 0) || (index >= length))
				return (null);
			return (_items.data[index]);
		}

		private void handle_is_valid (ParamSpec parm)
		{
			bool validity = true;
			for (int i=0; i<_items.data.length; i++) {
				if (_items.data[i].is_valid == false) {
					validity = false;
					break;
				}
			}
			if (validity != _last_valid_state) {
				_last_valid_state = validity;
				notify_property ("is-valid");
			}
		}

		public BindingInformation bind (string source_property, Object target, string target_property, BindingFlags flags = GLib.BindingFlags.DEFAULT, 
		                                owned BindingTransformFunc? transform_to = null, owned BindingTransformFunc? transform_from = null,
		                                owned SourceValidationFunc? source_validation = null)
		{
			BindingInformation info = new BindingInformation (this, source_property, target, target_property, flags, transform_to, transform_from, source_validation);
			_items.append_val (info);
			info.notify["is-valid"].connect (handle_is_valid);
			return (info);
		}

		public BindingInformation bind_default (string source_property, string target_property, BindingFlags flags = GLib.BindingFlags.DEFAULT, 
		                                        owned BindingTransformFunc? transform_to = null, owned BindingTransformFunc? transform_from = null,
		                                        owned SourceValidationFunc? source_validation = null)
		{
			BindingInformation info = new BindingInformation (this, source_property, _default_target, target_property, flags, transform_to, transform_from, source_validation);
			_items.append_val (info);
			info.notify["is-valid"].connect (handle_is_valid);
			return (info);
		}

		public void unbind (BindingInformation information)
		{
			for (int i=0; i<length; i++) {
				if (_items.data[i] == information) {
					information.notify["is-valid"].disconnect (handle_is_valid);
					_items.remove_index (i);
					information.unbind_connection();
					return;
				}
			}
		}

		public void unbind_all()
		{
			while (length > 0)
				unbind(get_item_at_index(0));
		}

		public signal void contract_changed (BindingContract contract);

		protected virtual void disconnect_contract()
		{
			finalizing_in_progress = true;
			clean_state_objects();
			clean_source_values();
			unbind_all();
			data = null;
		}

		private void handle_self_toggle_ref (Object obj, bool is_last)
		{
			if ((is_last == false) || (finalizing_in_progress == true))
				return;
			finalizing_in_progress = true;
			disconnect_contract();
			remove_toggle_ref (handle_self_toggle_ref);
		}

		public BindingContract.add_to_manager (BindingContractManager contract_manager, string name, Object? data = null, BindingReferenceType reference_type = BindingReferenceType.WEAK)
		{
			this (data, reference_type);
			contract_manager.add (name, this);
		}

		public BindingContract.add_to_default_manager (string name, Object? data = null, BindingReferenceType reference_type = BindingReferenceType.WEAK)
		{
			this.add_to_manager (BindingContractManager.get_default(), name, data, reference_type);
		}

		public BindingContract (Object? data = null, BindingReferenceType reference_type = BindingReferenceType.WEAK)
		{
			_reference_type = reference_type;
			contract_changed.connect ((src) => { 
				if (last_source.target == src.get_source())
					return;
				last_source = new WeakReference<Object?>(src.get_source());
			});
			this.data = data;
			add_toggle_ref (handle_self_toggle_ref);
			// no binding here yet, so nothing else is required
		}
	}

	// intentional implementation with non weak reference, since this allows to use
	// manager as reference holder
	internal class NamedContract
	{
		private string _name = "";
		public string name { 
			get { return (_name); } 
		}

		private BindingContract _contract;
		public BindingContract contract { 
			get { return (_contract); }
		}

		public void disconnect()
		{
			_contract = null;
		}

		~NamedContract()
		{
			disconnect();
		}

		public NamedContract (string name, BindingContract contract)
		{
			_name = name;
			_contract = contract;
		}
	}

	public class BindingContractManager : Object
	{
		private bool finalizing_in_progress = false;
		private static BindingContractManager _default_contract_manager = null;

		private GLib.Array<NamedContract> _contracts = new GLib.Array<NamedContract>();

		public static BindingContractManager get_default()
		{
			if (_default_contract_manager == null)
				_default_contract_manager = new BindingContractManager();
			return (_default_contract_manager);
		}

		public void clean()
		{
			while (_contracts.length > 0) {
				_contracts.data[0].disconnect();
				_contracts.remove_index(0);
			}
		}

		public BindingContract? get_contract (string name)
		{
			for (int i=0; i<_contracts.length; i++)
				if (_contracts.data[i].name == name)
					return (_contracts.data[i].contract);
			return (null);
		}

		public void add (string name, BindingContract contract)
		{
			if (get_contract(name) != null)
				return;
			_contracts.append_val (new NamedContract (name, contract));
		}

		public void remove (string name)
		{
			for (int i=0; i<_contracts.length; i++)
				if (_contracts.data[i].name == name)
					_contracts.remove_index (i);
		}

		private void handle_self_toggle_ref (Object obj, bool is_last)
		{
			if ((is_last == false) || (finalizing_in_progress == true))
				return;
			finalizing_in_progress = true;
			clean();
			remove_toggle_ref (handle_self_toggle_ref);
		}

		public BindingContractManager()
		{
			add_toggle_ref (handle_self_toggle_ref);
		}
	}
}
