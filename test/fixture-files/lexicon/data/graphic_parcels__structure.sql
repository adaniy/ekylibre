DROP TABLE IF EXISTS registered_graphic_parcels;

        CREATE TABLE registered_graphic_parcels (
          id character varying NOT NULL,
          city_name character varying,
          shape postgis.geometry(Polygon, 4326) NOT NULL,
          centroid postgis.geometry(Point, 4326)
        );

        CREATE INDEX ON registered_graphic_parcels (id);
        CREATE INDEX registered_graphic_parcels_shape ON registered_graphic_parcels USING GIST (shape);
        CREATE INDEX registered_graphic_parcels_centroid ON registered_graphic_parcels USING GIST (centroid);
