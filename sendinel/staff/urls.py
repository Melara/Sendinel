from django.conf.urls.defaults import *
from sendinel.web.views import *

urlpatterns = patterns("",
    url(r"^$", 'sendinel.staff.views.index', name = 'staff_index'),
    url(r"^list_infoservices/$", 'sendinel.staff.views.list_infoservices', 
        name = 'staff_list_infoservices'),
    url(r"^create_infomessage/(?P<id>\d+)/$", 'sendinel.staff.views.create_infomessage', 
        name = 'staff_create_infomessage')
    )