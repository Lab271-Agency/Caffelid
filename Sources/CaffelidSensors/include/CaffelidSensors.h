#ifndef CAFFELID_SENSORS_H
#define CAFFELID_SENSORS_H
#include <stddef.h>
typedef struct CaffelidTemperatureReader CaffelidTemperatureReader;
CaffelidTemperatureReader *caffelid_temperature_reader_create(void);
void caffelid_temperature_reader_destroy(CaffelidTemperatureReader *reader);
// Highest valid CPU/GPU reading in Celsius; never substitutes an old reading.
int caffelid_temperature_read(CaffelidTemperatureReader *reader, double *temperature, size_t *sensor_count);
#endif
