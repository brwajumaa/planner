public class Views.Today : Gtk.EventBox {
    private Views.Date date_view;
    private Gtk.Label date_label;

    construct {
        var today_icon = new Gtk.Image () {
            gicon = new ThemedIcon ("planner-today"),
            pixel_size = 24
        };

        var title_label = new Gtk.Label (_("Today"));
        title_label.get_style_context ().add_class ("header-title");

        date_label = new Gtk.Label (null) {
            margin_top = 2
        };

        var menu_image = new Widgets.DynamicIcon ();
        menu_image.size = 19;
        menu_image.update_icon_name ("dots-horizontal");
        
        var menu_button = new Gtk.Button () {
            valign = Gtk.Align.CENTER,
            can_focus = false
        };

        menu_button.add (menu_image);
        menu_button.get_style_context ().add_class (Gtk.STYLE_CLASS_FLAT);
        menu_button.clicked.connect (build_content_menu);

        var search_image = new Widgets.DynamicIcon ();
        search_image.size = 19;
        search_image.update_icon_name ("planner-search");
        
        var search_button = new Gtk.Button () {
            valign = Gtk.Align.CENTER,
            can_focus = false
        };
        search_button.get_style_context ().add_class (Gtk.STYLE_CLASS_FLAT);
        search_button.add (search_image);
        search_button.clicked.connect (Util.get_default ().open_quick_find);
        
        var header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
            valign = Gtk.Align.START,
            hexpand = true,
            margin_start = 20,
            margin_end = 6
        };

        header_box.pack_start (today_icon, false, false, 0);
        header_box.pack_start (title_label, false, false, 6);
        header_box.pack_start (date_label, false, false, 0);
        // header_box.pack_end (menu_button, false, false, 0);
        header_box.pack_end (search_button, false, false, 0);

        var magic_button = new Widgets.MagicButton ();

        date_view = new Views.Date (true) {
            margin_top = 12
        };

        var content = new Gtk.Grid () {
            orientation = Gtk.Orientation.VERTICAL,
            expand = true,
            margin_start = 16,
            margin_end = 36,
            margin_bottom = 36,
            margin_top = 6
        };
        content.add (header_box);
        content.add (date_view);

        var content_clamp = new Hdy.Clamp () {
            maximum_size = 720
        };

        content_clamp.add (content);

        var scrolled_window = new Gtk.ScrolledWindow (null, null) {
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            expand = true
        };
        scrolled_window.add (content_clamp);

        var overlay = new Gtk.Overlay () {
            expand = true
        };
        overlay.add_overlay (magic_button);
        overlay.add (scrolled_window);

        add (overlay);
        update_today_label ();
        show_all ();

        magic_button.clicked.connect (() => {
            prepare_new_item ();
        });

        scrolled_window.vadjustment.value_changed.connect (() => {
            if (scrolled_window.vadjustment.value > 20) {
                Planner.event_bus.view_header (true);
            } else {
                Planner.event_bus.view_header (false);
            }
        });

        Planner.event_bus.day_changed.connect (() => {
            date_view.update_date (new GLib.DateTime.now_local ());
            update_today_label ();
        });
    }

    private void update_today_label () {
        date_label.label = "%s %s".printf (new GLib.DateTime.now_local ().format ("%a"),
            new GLib.DateTime.now_local ().format (
            Granite.DateTime.get_default_date_format (false, true, false)
        ));
    }

    public void prepare_new_item (string content = "") {
        date_view.prepare_new_item (content);
    }

    public void build_content_menu () {
        Planner.event_bus.unselect_all ();

        var menu = new Dialogs.ContextMenu.Menu ();

        var show_completed_item = new Dialogs.ContextMenu.MenuItem (
            Planner.settings.get_boolean ("show-today-completed") ? _("Hide completed tasks") : _("Show completed tasks"),
            "planner-check-circle"
        );

        menu.add_item (show_completed_item);
        menu.popup ();

        show_completed_item.activate_item.connect (() => {
            menu.hide_destroy ();
            Planner.settings.set_boolean ("show-today-completed", !Planner.settings.get_boolean ("show-today-completed"));
        });
    }
}
