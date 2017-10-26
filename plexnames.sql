-- plexnames table for Mythtv-to-Plex conversions
-- 
-- Mythtv names often don't meet the standards that Plex needs to correctly identify TV shows
-- This table is used by mythtv_to_plex.sh to rename the files to meet Plex standards.
--
-- Example: (I like to use underscores. You might prefer spaces)
--
-- INSERT INTO `plexnames` (`title`, `plextitle`) VALUES('The Flash', 'The_Flash.2014');
-- INSERT INTO `plexnames` (`title`, `plextitle`) VALUES('Doctor Who', 'Doctor_Who.2005');
-- INSERT INTO `plexnames` (`title`, `plextitle`) VALUES('Gotham', 'Gotham');
-- INSERT INTO `plexnames` (`title`, `plextitle`) VALUES('Marvel\'s Agents of S.H.I.E.L.D.', 'Marvels_Agents_Of_SHIELD');

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";

--
-- Database: `mythconverg`
--

-- --------------------------------------------------------

--
-- Table structure for table `plexnames`
--

CREATE TABLE `plexnames` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `title` varchar(255) NOT NULL,
  `plextitle` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `plexnames`
--
ALTER TABLE `plexnames`
  ADD PRIMARY KEY (`id`);
