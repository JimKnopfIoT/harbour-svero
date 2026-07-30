// harbour-svero — read & chart Veroval blood-pressure measurements over USB.
#include <QtQuick>
#include <QGuiApplication>
#include <QQuickView>
#include <QQmlContext>
#include <sailfishapp.h>

#include "veroval.h"

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    QScopedPointer<QQuickView> view(SailfishApp::createView());

    Veroval veroval;
    view->rootContext()->setContextProperty(QStringLiteral("veroval"), &veroval);

    view->setSource(SailfishApp::pathTo(QStringLiteral("qml/harbour-svero.qml")));
    view->show();
    return app->exec();
}
