-- Convert schema '/home/marco/amw/AmuseWikiFarm/dbicdh/_source/deploy/85/001-auto.yml' to '/home/marco/amw/AmuseWikiFarm/dbicdh/_source/deploy/86/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE `node_aggregation` ADD COLUMN `sorting_pos` integer NOT NULL DEFAULT 0;

;
ALTER TABLE `node_aggregation_series` ADD COLUMN `sorting_pos` integer NOT NULL DEFAULT 0;

;
ALTER TABLE `node_category` ADD COLUMN `sorting_pos` integer NOT NULL DEFAULT 0;

;
ALTER TABLE `node_title` ADD COLUMN `sorting_pos` integer NOT NULL DEFAULT 0;

;

COMMIT;

