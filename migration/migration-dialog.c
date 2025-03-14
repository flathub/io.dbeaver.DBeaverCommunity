#include <gtk/gtk.h>
#include "resources.c"
#include <stdlib.h>

static void
activate (GtkApplication* app,
          int*        newUser)
{
  GtkBuilder *builder = gtk_builder_new_from_resource ("/io/dbeaver/migration/migration-dialog.ui");
  GtkWindow *window = GTK_WINDOW (gtk_builder_get_object(builder, "MigrationDialog"));
  GtkLinkButton *folderbutton = GTK_LINK_BUTTON (gtk_builder_get_object(builder, "LinkButton"));
  GtkButton *continue_btn = GTK_BUTTON (gtk_builder_get_object(builder, "continue_btn"));
  gtk_window_set_application(window, app);

  GtkCssProvider *provider = gtk_css_provider_new ();
  gtk_css_provider_load_from_resource (provider,
      "/io/dbeaver/migration/style.css");

   gtk_style_context_add_provider_for_screen(gdk_screen_get_default(),
                                             GTK_STYLE_PROVIDER(provider), GTK_STYLE_PROVIDER_PRIORITY_USER);


  char folderpath[1000] = "file://";
  strcat(folderpath, getenv("XDG_DATA_HOME"));
  gtk_link_button_set_uri(folderbutton, folderpath);

  g_signal_connect (continue_btn, "clicked", G_CALLBACK (gtk_window_close), window);

  if (*newUser == 1) {
    // New user mode (the default is the migration mode)
    printf("INFO: New user mode\n");
    GtkLabel *str_title = GTK_LABEL (gtk_builder_get_object(builder, "msg_title"));
    GtkLabel *str_subtitle = GTK_LABEL (gtk_builder_get_object(builder, "msg_subtitle"));

    gtk_label_set_label(str_title, "DBeaver is now Flatpak-friendly!");
    gtk_label_set_label(str_subtitle, "The default location for storing DBeaver's files has changed, and is now following XDG standards");
  } else {
    printf("INFO: Migration mode\n");
  }

  gtk_widget_set_visible(GTK_WIDGET(window),TRUE);
  g_object_unref (builder);
}

int
main (int    argc,
      char **argv)
{
  GtkApplication *app;
  int status;
  int newUser = 1;

  app = gtk_application_new ("io.dbeaver.DBeaverCommunity", G_APPLICATION_DEFAULT_FLAGS);
  if (argc >= 2 && strlen(argv[1]) == 1 && argv[1][0] == 'm') {
    // When the arg is 'm', move to migration mode
    newUser = 0;
  }
  g_signal_connect (app, "activate", G_CALLBACK (activate), &newUser);
  status = g_application_run (G_APPLICATION (app), 0, NULL);
  g_object_unref (app);

  return status;
}
