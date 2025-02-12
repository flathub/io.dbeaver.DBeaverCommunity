#include <gtk/gtk.h>
#include "resources.c"
#include <stdlib.h>
#include <adwaita.h>

static void
activate (GtkApplication* app,
          gpointer        user_data)
{
  GtkBuilder *builder = gtk_builder_new_from_resource ("/io/dbeaver/migration/migration-dialog.ui");
  GtkWindow *window = GTK_WINDOW (gtk_builder_get_object(builder, "MigrationDialog"));
  GtkLinkButton *folderbutton = GTK_LINK_BUTTON (gtk_builder_get_object(builder, "LinkButton"));
  gtk_window_set_application(window, app);

  char folderpath[1000] = "file://";
  strcat(folderpath, getenv("XDG_DATA_HOME"));
  gtk_link_button_set_uri(folderbutton, folderpath);

  gtk_widget_set_visible(GTK_WIDGET(window),TRUE);
  g_object_unref (builder);
}

int
main (int    argc,
      char **argv)
{
  AdwApplication *app;
  int status;

  app = adw_application_new ("io.dbeaver.DBeaverCommunity", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect (app, "activate", G_CALLBACK (activate), NULL);
  status = g_application_run (G_APPLICATION (app), argc, argv);
  g_object_unref (app);

  return status;
}
