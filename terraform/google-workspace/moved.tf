# Resource addresses of the previous version of this module, so an existing
# deployment keeps its objects. To keep their names too, see "Upgrading from the
# previous version" in ../google-cloud/README.md. Remove this file once every
# deployment has been applied on this version (target: 2027-04).

moved {
  from = googleworkspace_role.BritiveIntegration
  to   = googleworkspace_role.britive
}

moved {
  from = googleworkspace_user.BritiveIntegration
  to   = googleworkspace_user.britive
}

moved {
  from = googleworkspace_role_assignment.BritiveIntegration
  to   = googleworkspace_role_assignment.britive
}

moved {
  from = random_password.password
  to   = random_password.admin
}
