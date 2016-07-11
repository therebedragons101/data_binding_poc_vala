using Gtk.Fx;

public class Person : Object
{
	public string name { get; set; }
	public string surname { get; set; }
	public string required { get; set; }
	
	public Person (string name, string surname, string required = "")
	{
		this.name = name;
		this.surname = surname;
		this.required = required;
	}
}

// only for purpose of accessing contract trough gtk-inspector
public class BindingListBoxRow : Gtk.ListBoxRow
{
	public BindingContract contract {
		get { return (get_data<BindingContract>("binding-contract")); }
	}
}

public class test_data_bindings : Gtk.Application
{
	private ObjectArray<Person> _persons = new ObjectArray<Person>();
	public ObjectArray<Person> persons {
		get { return (_persons); }
	}
	
	private Gtk.Window window;
	private Gtk.ListBox items;
	private Gtk.Entry name;
	private Gtk.Entry surname;
	private Gtk.Entry required;
	private Gtk.Button required_not_empty;
	private Gtk.Button is_valid_source;
	private Gtk.Label name_chain;
	private Gtk.Label surname_chain;
	private Gtk.Label custom_data;

	private BindingContract _selection_contract;
	public BindingContract selection_contract {
		get { return (_selection_contract); }
	}
	
	private BindingContract _chain_contract;
	public BindingContract chain_contract {
		get { return (_chain_contract); }
	}
	
	public test_data_bindings ()
	{
		Object (flags: ApplicationFlags.FLAGS_NONE);
	}

	protected override void startup ()
	{
		base.startup ();

		Environment.set_application_name ("test_data_bindings");

		var ui_builder = new Gtk.Builder ();
		try {
			ui_builder.add_from_file ("./interface.ui");
		}
		catch (Error e) { warning ("Could not load game UI: %s", e.message); }
		
		window = (Gtk.Window) ui_builder.get_object ("firstWindow");
		add_window (window);
		
		items = (Gtk.ListBox) ui_builder.get_object ("items");
		name = (Gtk.Entry) ui_builder.get_object ("name");
		surname = (Gtk.Entry) ui_builder.get_object ("surname");
		required = (Gtk.Entry) ui_builder.get_object ("required");
		name_chain = (Gtk.Label) ui_builder.get_object ("name_chain");
		surname_chain = (Gtk.Label) ui_builder.get_object ("surname_chain");
		custom_data = (Gtk.Label) ui_builder.get_object ("custom_data");
		
		_selection_contract = new BindingContract(null);
		selection_contract.bind ("name", name, "text", GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL, null, null,
			((v) => {
				return ((string) v != "");
			}));
		selection_contract.bind ("surname", surname, "text", GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL, null, null,
			((v) => {
				return ((string) v != "");
			}));
		selection_contract.bind ("required", required, "text", GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);
		
		// chaining contract as source
		_chain_contract = new BindingContract(selection_contract);
		chain_contract.bind ("name", name_chain, "label", GLib.BindingFlags.SYNC_CREATE);
		chain_contract.bind ("surname", surname_chain, "label", GLib.BindingFlags.SYNC_CREATE);

		items.bind_model (persons, ((o) => {
			Gtk.ListBoxRow r = new BindingListBoxRow();
			r.set_data<WeakReference<Person?>>("person", new WeakReference<Person?>((Person) o));
			r.visible = true;
			Gtk.Box box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
			box.visible = true;
			r.add (box);
			Gtk.Label name = new Gtk.Label("");
			name.visible = true;
			Gtk.Label surname = new Gtk.Label("");
			surname.visible = true;
			box.pack_start (name);
			box.pack_start (surname);

			// This is just wrong, it is like that only for stress test purpose. 
			// Simply use default basic binding provided with Object.bind_property would be better
			// since in this case source will never change
			BindingContract contract = new BindingContract (o);
			contract.bind ("name", name, "label", GLib.BindingFlags.SYNC_CREATE);
			contract.bind ("surname", surname, "label", GLib.BindingFlags.SYNC_CREATE);

			// This would be much more suitable in this use case
			//o.bind_property ("name", name, "label", GLib.BindingFlags.SYNC_CREATE);
			//o.bind_property ("surname", surname, "label", GLib.BindingFlags.SYNC_CREATE);

			r.set_data<BindingContract> ("binding-contract", contract);
			return (r);
		}));
		persons.add (new Person("John", "Doe"));
		persons.add (new Person("Somebody", "Nobody"));
		persons.add (new Person("Intentionally_Invalid_State", "", "Nobody"));

		// adding custom state value to contract
		selection_contract.add_state (new CustomBindingSourceState ("validity", selection_contract, ((src) => {
			return ((src.data != null) && (((Person) src.data).required != ""));
		}), new string[1] { "required" }));

		// adding custom value to contract
		selection_contract.add_source_value (new CustomBindingSourceData<string> ("length", selection_contract, 
			((src) => {
				return ("(cumulative of string lengths)=>%i".printf((src.data != null) ? ((Person) src.data).name.length + ((Person) src.data).surname.length + ((Person) src.data).required.length : 0));
			}), 
			((a,b) => { return ((a == b) ? 0 : 1); }), 
			"", false, ALL_PROPERTIES));

		required_not_empty = (Gtk.Button) ui_builder.get_object ("required_not_empty");
		is_valid_source = (Gtk.Button) ui_builder.get_object ("is_valid_source");

		// bind to state. note that state is updated whenever contract source changes or specified properties in respective class get changed
		// which makes it perfectly ok to use simple binding as this connection will be stable for whole contract life
		selection_contract.get_state_object("validity").bind_property ("state", required_not_empty, "sensitive", GLib.BindingFlags.SYNC_CREATE);

		// bind to binding value. note that value is updated whenever contract source changes or specified properties in respective class get changed
		// which makes it perfectly ok to use simple binding as this connection will be stable for whole contract life
		selection_contract.get_source_value ("length").bind_property ("data", custom_data, "label", GLib.BindingFlags.SYNC_CREATE, 
			(binding, srcval, ref targetval) => {
				targetval.set_string (((CustomBindingSourceData<string>) binding.source).data);
				return true;
			});

		selection_contract.bind_property ("is-valid", is_valid_source, "sensitive", GLib.BindingFlags.SYNC_CREATE);

		items.row_selected.connect ((r) => {
			selection_contract.data = (r != null) ? (r.get_data<WeakReference<Person?>>("person")).target : null;
		});
	}

	protected override void shutdown ()
	{
		base.shutdown ();
	}

	protected override void activate ()
	{
		window.present ();
	}

	public static int main (string[] args)
	{
		var app = new test_data_bindings ();
		return (app.run (args));
	}
}
