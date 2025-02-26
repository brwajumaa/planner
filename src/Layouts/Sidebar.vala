public class Layouts.Sidebar : Gtk.EventBox {
    private Gtk.FlowBox listbox;
    private Gtk.Grid listbox_grid;

    private Layouts.FilterPaneRow inbox;
    private Layouts.FilterPaneRow today;
    private Layouts.FilterPaneRow scheduled;
    private Layouts.FilterPaneRow pinboard;

    private Layouts.HeaderItem favorites_header;
    private Layouts.HeaderItem projects_header;
    private Layouts.HeaderItem labels_header;
    private Gtk.Grid main_grid;
    
    public Gee.HashMap <string, Layouts.ProjectRow> projects_hashmap;
    public Gee.HashMap <string, Layouts.ProjectRow> favorites_hashmap;

    private Gee.HashMap <string, Layouts.HeaderItem> collection_hashmap;
    private Gee.Collection<E.Source>? collection_sources;

    private Gee.HashMap<E.Source, Layouts.TasklistRow>? source_rows;
    private Gee.HashMap<string, E.Source>? source_uids = null;

    public signal void valid_tasklist_removed (E.Source source);
    public signal void caldav_finished ();

    construct {
        projects_hashmap = new Gee.HashMap <string, Layouts.ProjectRow> ();
        favorites_hashmap = new Gee.HashMap <string, Layouts.ProjectRow> ();

        listbox = new Gtk.FlowBox () {
            column_spacing = 9,
            row_spacing = 9,
            homogeneous = true,
            hexpand = true,
            max_children_per_line = 2,
            min_children_per_line = 2
        };
        
        unowned Gtk.StyleContext listbox_context = listbox.get_style_context ();
        listbox_context.add_class ("padding-3");

        listbox_grid = new Gtk.Grid () {
            margin = 6,
            margin_bottom = 6,
            margin_top = 0
        };
        listbox_grid.add (listbox);

        inbox = new Layouts.FilterPaneRow (FilterType.INBOX);
        today = new Layouts.FilterPaneRow (FilterType.TODAY);
        scheduled = new Layouts.FilterPaneRow (FilterType.SCHEDULED);
        pinboard = new Layouts.FilterPaneRow (FilterType.PINBOARD);

        listbox.add (inbox);
        listbox.add (today);
        listbox.add (scheduled);
        listbox.add (pinboard);

        favorites_header = new Layouts.HeaderItem (PaneType.FAVORITE);
        favorites_header.add_action = false;

        projects_header = new Layouts.HeaderItem (PaneType.PROJECT);

        labels_header = new Layouts.HeaderItem (PaneType.LABEL);

        main_grid = new Gtk.Grid () {
            orientation = Gtk.Orientation.VERTICAL
        };

        var scrolled_window = new Gtk.ScrolledWindow (null, null) {
            hscrollbar_policy = Gtk.PolicyType.NEVER
        };
        scrolled_window.expand = true;
        scrolled_window.add (main_grid);

        add (scrolled_window);
        update_projects_sort ();

        projects_header.add_activated.connect (() => {
            prepare_new_project ();
        });

        labels_header.add_activated.connect (() => {
            prepare_new_label ();
        });

        Planner.settings.changed.connect ((key) => {
            if (key == "projects-sort-by" || key == "projects-ordered") {
                update_projects_sort ();
            }
        });
    }

    private void update_projects_sort () {
        BackendType backend_type = (BackendType) Planner.settings.get_enum ("backend-type");

        if (backend_type == BackendType.LOCAL || backend_type == BackendType.TODOIST) {
            if (Planner.settings.get_enum ("projects-sort-by") == 0) {
                projects_header.set_sort_func (projects_sort_func);
            } else {
                projects_header.set_sort_func (null);
            }
        } else if (backend_type == BackendType.CALDAV) {
            foreach (var entry in collection_hashmap.entries) {
                if (Planner.settings.get_enum ("projects-sort-by") == 0) {
                    entry.value.set_sort_func (tasklist_sort_func);
                } else {
                    entry.value.set_sort_func (null);
                }
            }
        }
    }

    private int projects_sort_func (Gtk.ListBoxRow lbrow, Gtk.ListBoxRow lbbefore) {
        Objects.Project project1 = ((Layouts.ProjectRow) lbrow).project;
        Objects.Project project2 = ((Layouts.ProjectRow) lbbefore).project;

        if (Planner.settings.get_enum ("projects-ordered") == 0) {
            return project2.name.collate (project1.name);
        } else {
            return project1.name.collate (project2.name);
        }
    }

    private int tasklist_sort_func (Gtk.ListBoxRow lbrow, Gtk.ListBoxRow lbbefore) {
        E.Source project1 = ((Layouts.TasklistRow) lbrow).source;
        E.Source project2 = ((Layouts.TasklistRow) lbbefore).source;

        if (Planner.settings.get_enum ("projects-ordered") == 0) {
            return project2.display_name.collate (project1.display_name);
        } else {
            return project1.display_name.collate (project2.display_name);
        }
    }

    private void prepare_new_project () {
        var dialog = new Dialogs.Project.new ();
        dialog.show_all ();
    }

    private void prepare_new_label () {
        var dialog = new Dialogs.Label.new ();
        dialog.show_all ();
    }

    public void init (BackendType backend_type) {
        if (backend_type == BackendType.LOCAL || backend_type == BackendType.TODOIST) {
            main_grid.add (listbox_grid);
            main_grid.add (favorites_header);
            main_grid.add (projects_header);
            main_grid.add (labels_header);

            // Init signals
            Planner.database.project_added.connect (add_row_project);
            Planner.database.project_updated.connect (update_projects_sort);
            Planner.database.label_added.connect (add_row_label);
            Planner.event_bus.project_parent_changed.connect ((project, old_parent_id) => {
                if (old_parent_id == Constants.INACTIVE) {
                    if (projects_hashmap.has_key (project.id_string)) {
                        projects_hashmap [project.id_string].hide_destroy ();
                        projects_hashmap.unset (project.id_string);
                    }
                }

                if (project.parent_id == Constants.INACTIVE) {
                    add_row_project (project);
                }
            });

            Planner.event_bus.favorite_toggled.connect ((project) => {
                if (favorites_hashmap.has_key (project.id_string)) {
                    favorites_hashmap [project.id_string].hide_destroy ();
                    favorites_hashmap.unset (project.id_string);
                } else {
                    add_row_favorite (project);
                }
            });

            // Get projects
            add_all_projects ();
            add_all_favorites ();
            add_all_labels ();

            inbox.init ();
            today.init ();
            scheduled.init ();
            pinboard.init ();

            main_grid.show_all ();
        } else if (backend_type == BackendType.CALDAV) {
            main_grid.add (listbox_grid);

            Services.CalDAV.get_default ().get_registry.begin ((obj, res) => {
                E.SourceRegistry registry;
                try {
                    registry = Services.CalDAV.get_default ().get_registry.end (res);
                } catch (Error e) {
                    critical (e.message);
                    return;
                }

                add_collection_source (registry.ref_builtin_task_list ());
                var task_list_collections = registry.list_sources (E.SOURCE_EXTENSION_COLLECTION);
                task_list_collections.foreach ((collection_source) => {
                    add_collection_source (collection_source);
                });

                var task_lists = registry.list_sources (E.SOURCE_EXTENSION_TASK_LIST);
                task_lists.foreach ((source) => {
                    E.SourceTaskList list = (E.SourceTaskList)source.get_extension (E.SOURCE_EXTENSION_TASK_LIST);
                    if (list.selected == true && source.enabled == true && !source.has_extension (E.SOURCE_EXTENSION_COLLECTION)) {
                        add_source (source);
                    }
                });

                Services.AccountsModel.get_default ().esource_removed.connect (remove_esource);
                Services.AccountsModel.get_default ().esource_added.connect ((collection_source) => {
                    add_collection_source (collection_source);
                });

                Services.CalDAV.get_default ().task_list_added.connect (add_source);
                Services.CalDAV.get_default ().task_list_modified.connect (update_source);
                Services.CalDAV.get_default ().task_list_removed.connect (remove_source);

                inbox.init ();
                today.init ();
                scheduled.init ();
                caldav_finished ();
            }); 
        }
    }

    private void add_row_project (Objects.Project project) {
        if (!project.inbox_project && project.parent_id == Constants.INACTIVE) {
            if (!projects_hashmap.has_key (project.id_string)) {
                projects_hashmap [project.id_string] = new Layouts.ProjectRow (project);
                projects_header.add_child (projects_hashmap [project.id_string]);
            }
        }
    }

    private void add_all_projects () {
        foreach (Objects.Project project in Planner.database.projects) {
            add_row_project (project);
        }

        projects_header.init_update_position_project ();
    }

    private void add_all_favorites () {
        foreach (Objects.Project project in Planner.database.projects) {
            add_row_favorite (project);
        }
    }

    private void add_row_favorite (Objects.Project project) {
        if (project.is_favorite) {
            if (!favorites_hashmap.has_key (project.id_string)) {
                favorites_hashmap [project.id_string] = new Layouts.ProjectRow (project, false);
                favorites_header.add_child (favorites_hashmap [project.id_string]);
            }
        }
    }

    private void add_all_labels () {
        foreach (Objects.Label label in Planner.database.labels) {
            add_row_label (label);
        }
    }

    private void add_row_label (Objects.Label label) {
        labels_header.add_child (new Layouts.LabelRow (label));
    }

    private void add_collection_source (E.Source collection_source) {
        if (collection_hashmap == null) {
            collection_hashmap = new Gee.HashMap <string, Layouts.HeaderItem> ();
        }

        if (collection_sources == null) {
            collection_sources = new Gee.HashSet<E.Source> (CalDAVUtil.esource_hash_func, CalDAVUtil.esource_equal_func);
        }

        E.SourceTaskList collection_source_tasklist_extension = (E.SourceTaskList) collection_source.get_extension (E.SOURCE_EXTENSION_TASK_LIST);

        if (collection_sources.contains (collection_source) ||
            !collection_source.enabled ||
            !collection_source_tasklist_extension.selected) {
            return;
        }

        var header_item = new Layouts.HeaderItem (PaneType.TASKLIST, CalDAVUtil.get_esource_collection_display_name (collection_source));

        header_item.add_activated.connect (() => {
            add_new_list (collection_source, header_item);
        });
        
        collection_hashmap[collection_source.dup_uid ()] = header_item;
        collection_sources.add (collection_source);

        main_grid.add (header_item);
        main_grid.show_all ();
    }

    private void add_source (E.Source source) {        
        if (source_rows == null) {
            source_rows = new Gee.HashMap<E.Source, Layouts.TasklistRow> ();
        }

        if (source_uids == null) {
            source_uids = new Gee.HashMap<string, E.Source> ();
        }

        if (collection_hashmap == null) {
            collection_hashmap = new Gee.HashMap <string, Layouts.HeaderItem> ();
        }

        debug ("Adding row '%s'", source.dup_display_name ());
        if (!source_rows.has_key (source)) {
            source_rows[source] = new Layouts.TasklistRow (source);
            source_uids[source.uid] = source;

            string collection = source.parent;
            if (collection == "local-stub") {
                collection = "system-task-list";
            }

            if (collection_hashmap.has_key (collection) && source.uid != "system-task-list") {
                collection_hashmap [collection].add_child (source_rows[source]);
            }

            main_grid.show_all ();
        }
    }

    private void update_source (E.Source source) {
        E.SourceTaskList list = (E.SourceTaskList)source.get_extension (E.SOURCE_EXTENSION_TASK_LIST);

        if (list.selected != true || source.enabled != true) {
            remove_source (source);
        } else if (!source_rows.has_key (source)) {
            add_source (source);
        } else {
            source_rows[source].update_request ();
        }

        update_projects_sort ();
    }

    private void remove_source (E.Source source) {
        if (source_rows.has_key (source)) {
            valid_tasklist_removed (source);
            source_rows[source].hide_destroy ();
            source_rows.unset (source);
        }

        if (source_uids.has_key (source.uid)) {
            source_uids.unset (source.uid);
        }
    }

    private void remove_esource (E.Source source) {
        if (collection_hashmap.has_key (source.dup_uid ())) {
            collection_hashmap[source.dup_uid ()].destroy ();
        }
    }

    public E.Source? get_source (string uid) {
        if (source_uids.has_key (uid)) {
            return source_uids[uid];
        }

        return null;
    }

    private void add_new_list (E.Source collection_source, Layouts.HeaderItem header_item) {
        var error_dialog_primary_text = _("Creating a new task list failed");
        var error_dialog_secondary_text = _("The task list registry may be unavailable or unable to be written to.");

        try {
            header_item.is_loading = true;

            var new_source = new E.Source (null, null);
            var new_source_tasklist_extension = (E.SourceTaskList) new_source.get_extension (E.SOURCE_EXTENSION_TASK_LIST);
            new_source.display_name = _("New list");
            new_source_tasklist_extension.color = Util.get_default ().get_color (Util.get_default ().get_random_color ());

            Services.CalDAV.get_default ().add_task_list.begin (new_source, collection_source, (obj, res) => {
                try {
                    Services.CalDAV.get_default ().add_task_list.end (res);
                    header_item.is_loading = false;
                } catch (Error e) {
                    critical (e.message);
                    show_error_dialog (error_dialog_primary_text, error_dialog_secondary_text, e);
                }
            });

        } catch (Error e) {
            critical (e.message);
            show_error_dialog (error_dialog_primary_text, error_dialog_secondary_text, e);
        }
    }

    private void show_error_dialog (string primary_text, string secondary_text, Error e) {
        string error_message = e.message;

        GLib.Idle.add (() => {
            var error_dialog = new Granite.MessageDialog (
                primary_text,
                secondary_text,
                new ThemedIcon ("dialog-error"),
                Gtk.ButtonsType.CLOSE
            );
            
            error_dialog.show_error_details (error_message);
            error_dialog.run ();
            error_dialog.destroy ();

            return GLib.Source.REMOVE;
        });
    }
}
