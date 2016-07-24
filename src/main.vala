using G;

public class PersonInfo : Object
{
	public int some_num { get; set; }
}

public class Person : Object
{
	public string name { get; set; }
	public string surname { get; set; }
	public string required { get; set; }

	public PersonInfo info { get; set; }
	public Person parent { get; set; }

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
	private string _title_css = """
		* {
			border: solid 2px gray;
			padding: 4px 4px 4px 4px;
			border-radius: 5px;
			color: rgba (255,255,255,0.7);
			background-color: rgba(0,0,0,0.09);
		}
	""";

	private string _dark_label_css = """
		* {
			border-radius: 5px;
			padding: 4px 4px 4px 4px;
			color: rgba (255,255,255,0.7);
			background-color: rgba(0,0,0,0.2);
		}
	""";

	private string _warning_label_css = """
		* {
			border: solid 1px rgba (0,0,0,1);
			padding: 4px 4px 4px 4px;
			border-radius: 5px;
			color: rgba (255,255,255,0.7);
			background-color: rgba(255,0,0,0.05);
		}
	""";

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
	private Gtk.HeaderBar demo_headerbar;

	private Gtk.Entry basic_entry_left;
	private Gtk.Entry basic_entry_right;
	private Gtk.Entry basic_entry_left2;
	private Gtk.Entry basic_entry_right2;
	private Gtk.Label basic_label_left3;
	private Gtk.Entry basic_entry_right3;
	private Gtk.Label basic_label_right4;
	private Gtk.ToggleButton basic_flood_data_btn;
	private Gtk.Entry basic_entry_left5;
	private Gtk.Label basic_label_right5;
	private Gtk.Button basic_transfer_data_btn;

	private BindingContract _selection_contract;
	public BindingContract selection_contract {
		get { return (_selection_contract); }
	}
	
	private BindingContract _chain_contract;
	public BindingContract chain_contract {
		get { return (_chain_contract); }
	}

	private int _counter = 0;
	public string counter {
		owned get { return ("counter=%i".printf(_counter)); }
	}

	public Gtk.CssProvider? assign_css (Gtk.Widget? widget, string css_content)
		requires (widget != null)
	{
		Gtk.CssProvider provider = new Gtk.CssProvider();
		try {
			provider.load_from_data(css_content, css_content.length);
			Gtk.StyleContext style = widget.get_style_context();
			style.add_provider (provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
		}
		catch (Error e) { print ("Could not load CSS. %s\n", e.message); }
		return (provider);
	}

	public void assign_builder_css (Gtk.Builder ui_builder, string widget_name, string css)
	{
		string wname = widget_name;
		Gtk.Widget w = (Gtk.Widget) ui_builder.get_object (wname);
		while (w != null) {
			assign_css (w, css);
			wname += "_";
			w = (Gtk.Widget) ui_builder.get_object (wname);
		}
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

		demo_headerbar = (Gtk.HeaderBar) ui_builder.get_object ("demo_headerbar");
		window.set_titlebar (demo_headerbar);

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

		assign_builder_css (ui_builder, "label_description", _dark_label_css);
		assign_builder_css (ui_builder, "label_warning", _warning_label_css);
		assign_builder_css (ui_builder, "custom_data", _title_css);

		example1(ui_builder);
	}

	public bool flood_timer()
	{
		_counter++;
		this.notify_property("counter");
		return (basic_flood_data_btn.active);
	}

	public void flooded (BindingInterface binding)
	{
		basic_label_right4.sensitive = false;
		basic_label_right4.label = "*** FLOODING *** last before freeze=>%i".printf(_counter);
	}

	public void flood_over (BindingInterface binding)
	{
		basic_label_right4.sensitive = true;
	}

	public void example1 (Gtk.Builder ui_builder)
	{
		basic_entry_left = (Gtk.Entry) ui_builder.get_object ("basic_entry_left");
		basic_entry_right = (Gtk.Entry) ui_builder.get_object ("basic_entry_right");
		PropertyBinding.bind (basic_entry_left, "text", basic_entry_right, "text", BindFlags.SYNC_CREATE);

		basic_entry_left2 = (Gtk.Entry) ui_builder.get_object ("basic_entry_left2");
		basic_entry_right2 = (Gtk.Entry) ui_builder.get_object ("basic_entry_right2");
		PropertyBinding.bind (basic_entry_left2, "text", basic_entry_right2, "text", BindFlags.BIDIRECTIONAL | BindFlags.SYNC_CREATE);

		basic_label_left3 = (Gtk.Label) ui_builder.get_object ("basic_label_left3");
		basic_entry_right3 = (Gtk.Entry) ui_builder.get_object ("basic_entry_right3");
		PropertyBinding.bind (basic_label_left3, "label", basic_entry_right3, "text", BindFlags.REVERSE_DIRECTION | BindFlags.SYNC_CREATE);

		basic_label_right4 = (Gtk.Label) ui_builder.get_object ("basic_label_right4");
		PropertyBinding basic4 = PropertyBinding.bind (this, "counter", basic_label_right4, "label", BindFlags.FLOOD_DETECTION | BindFlags.SYNC_CREATE);
		basic4.flood_detected.connect (flooded);
		basic4.flood_stopped.connect (flood_over);
		basic_flood_data_btn = (Gtk.ToggleButton) ui_builder.get_object ("basic_flood_data_btn");
		basic_flood_data_btn.toggled.connect (() => {
			if (basic_flood_data_btn.active == true)
				GLib.Timeout.add (20, flood_timer, GLib.Priority.DEFAULT);
		});

		basic_entry_left5 = (Gtk.Entry) ui_builder.get_object ("basic_entry_left5");
		basic_label_right5 = (Gtk.Label) ui_builder.get_object ("basic_label_right5");
		PropertyBinding basic5 = PropertyBinding.bind (basic_entry_left5, "text", basic_label_right5, "label", BindFlags.MANUAL_UPDATE | BindFlags.SYNC_CREATE);
		basic_transfer_data_btn = (Gtk.Button) ui_builder.get_object ("basic_transfer_data_btn");
		basic_transfer_data_btn.clicked.connect (() => {
			basic5.update_from_source();
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
