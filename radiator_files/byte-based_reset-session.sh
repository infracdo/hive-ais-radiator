#!/bin/bash

# PostgreSQL DB credentials
DB_NAME="radius"
#DB_USER="your_db_user"
PG_USER="postgres"

# Run the SQL command
RESET="psql -d \"$DB_NAME\" -c \"UPDATE subscribers SET remaining_bytes = bytes_limit WHERE remaining_bytes >= 0;\""
#RESET="psql -d "$DB_NAME" -c "UPDATE test SET remaining_session_time = session_limit, last_reset = now() WHERE remaining_session_time = 0 AND last_reset < now() - INTERAL '5 minutes';""

#SWITCH TO POSTGRES USER AND RUN COMMAND
sudo su - $PG_USER bash -c "$RESET"

#checking
if [ $? -eq 0 ]; then
  echo "reset completed successfully."
else
  echo "reset failed."
fi
