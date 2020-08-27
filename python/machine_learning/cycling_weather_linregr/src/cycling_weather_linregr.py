#!/usr/bin/env python3

"""
SOURCE FOR DATA AND ASSIGNMENT:
University of Helsinki, course Data Analysis with Python 2020
Link to course description:
https://courses.helsinki.fi/fi/aycsm90004en/135221588

EXERCISE 13 (cycling weather continues)
Write function cycling_weather_continues that tries to explain with linear
regression the variable of a cycling measuring station’s counts using the
weather data from corresponding day.

The function should take the name of a (cycling) measuring station as a
parameter and return the regression coefficients and the score.

In more detail:
* Read the weather data set from the src folder.
* Read the cycling data set from folder src and restrict it to year 2017.
* Further, get the sums of cycling counts for each day.
* Merge the two datasets by the year, month, and day.

Note that for the above you need only small additions to the solution of
exercise cycling_weather. After this, use forward fill to fill the missing
values.

In the linear regression use as explanatory variables the following columns:
'Precipitation amount (mm)', 'Snow depth (cm)', and 'Air temperature (degC)'.

Explain the variable (measuring station), whose name is given as a parameter to
the function cycling_weather_continues. Fit also the intercept.

The function should return a pair, whose first element is the regression
coefficients and the second element is the score. Above, you may need to use the
method reset_index (its counterpart is the method set_index).

The output from the main function should be in the following form:

Measuring station: x
Regression coefficient for variable 'precipitation': x.x
Regression coefficient for variable 'snow depth': x.x
Regression coefficient for variable 'temperature': x.x
Score: x.xx

Use precision of one decimal for regression coefficients, and precision of two
decimals for the score.

In the main function test you solution using some measuring station, for example
Baana.

Possible improvements:
- Enable giving the target measuring station as command line argument
"""

import pandas as pd
from sklearn.linear_model import LinearRegression


def create_date_column(paivamaara_series: pd.Series):
    """
    Creates a Pandas datetime column from the original cycling data's
    Päivämäärä column.

    Parameters:
    - paivamaara_series: Pandas Series with the Päivämäärä column from the
        original data

    Returns:
    - date_series: Pandas Series with the same information as Päivämäärä but
        as Pandas datetime
    """

    # Split Päivämäärä column
    date_df = paivamaara_series.str.split(expand=True)
    date_df.columns = ['Weekday', 'Day', 'Month', 'Year', 'Hour']

    # Map weekday and month from Finnish text
    weekday_map = {
        "ma": "Mon",
        "ti": "Tue",
        "ke": "Wed",
        "to": "Thu",
        "pe": "Fri",
        "la": "Sat",
        "su": "Sun"
    }

    month_map = {
        "tammi": 1,
        "helmi": 2,
        "maalis": 3,
        "huhti": 4,
        "touko": 5,
        "kesä": 6,
        "heinä": 7,
        "elo": 8,
        "syys": 9,
        "loka": 10,
        "marras": 11,
        "joulu": 12
    }

    date_df.iloc[:, 0] = date_df.iloc[:, 0].map(arg=weekday_map)
    date_df.iloc[:, 2] = date_df.iloc[:, 2].map(arg=month_map)

    # Drop minute information from timestamp
    date_df.iloc[:, 4] = date_df.iloc[:, 4] \
        .str.split(":") \
        .apply(lambda x: x[0]) \
        .astype(int)

    # Convert remaining number strings to int
    date_df = date_df.astype({"Day": int, "Year": int})

    date_series = pd.to_datetime(date_df[["Year", "Month", "Day", "Hour"]])

    return date_series


def get_cycling_timeseries_2017(station: str):
    """
    Calculates count of daily cyclists for the station given as parameter in
    2017.

    Assumes data is available in same folder as this script. Reads data,
    reindexes using a Pandas datetime column and calculates daily counts of
    cyclists.

    Parameters:
    - station: Name of measuring station to evaluate. Needs to be one of the
        columns in the source data (e.g. "Baana" or "Merikannontie")

    Returns:
    - cycling_df: DataFrame with daily counts of cyclists at the measuring
        station
    """

    # Load data
    cycling_df = pd.read_csv("src/Helsingin_pyorailijamaarat.csv", sep=";")

    # Drop rows and columns with only null values
    cycling_df = cycling_df \
        .dropna(axis=0, how="all") \
        .dropna(axis=1, how="all")

    # Create Date column and reindex dataset
    cycling_df["Date"] = create_date_column(cycling_df["Päivämäärä"])
    cycling_df = cycling_df.set_index("Date")

    # Drop redundan
    cycling_df.drop(["Päivämäärä"], axis="columns", inplace=True)

    cycling_df = cycling_df.loc['2017', station]

    cycling_df = cycling_df \
        .groupby(cycling_df.index.date) \
        .sum()

    return cycling_df


def get_weather_timeseries_2017():
    """
    Creates a datetime-indexed DataFrame of weather data per day in 2017.

    Assumes data is available in same folder as this script. Reads data and
    reindexes using a Pandas datetime column.

    Parameters:
    None

    Returns:
    - weather_df: Pandas DataFrame with a datetime index for daily weather data
    """
    weather_df = pd.read_csv("src/kumpula-weather-2017.csv")

    # -1 value in columns "Precipitation amount (mm)" and "Snow depth (cm)" mean
    # that there was no absolutely no rain or snow that day, whereas 0 can mean
    # a little of either. Let's convert the -1 values to 0 to make the dataset
    # more logical to read.
    weather_df.loc[weather_df["Precipitation amount (mm)"] == -1,
           "Precipitation amount (mm)"] = 0
    weather_df.loc[weather_df["Snow depth (cm)"] == -1, "Snow depth (cm)"] = 0

    # Create datetime index
    weather_df["Month"] = weather_df["m"]
    weather_df["Day"] = weather_df["d"]
    weather_df["Date"] = pd.to_datetime(weather_df[["Year", "Month", "Day"]])

    # Reindex dataset
    weather_df = weather_df.set_index("Date")

    # Drop redundant columns
    weather_df.drop(["Time", "Time zone", "m", "d", "Year",
             "Month", "Day"], axis="columns", inplace=True)

    return weather_df


def cycling_weather_linregr(station: str):
    """
    Runs linear regression comparing daily weather data against cyclist counts
    at a specific measuring station in Helsinki.

    Parameters:
    - station: Name of measuring station to evaluate. Needs to be one of the
        columns in the source data (e.g. "Baana" or "Merikannontie")

    Returns:
    - tuple(model.coef_): Tuple of coefficients for each of the predicting
        variables (precipitation, snow depth, temperature) for the linear model
    - r2: R2 value for the linear model
    """

    # Create a merged dataset of weather data and
    # daily cyclists at the measuring station given as
    # parameter

    cycling_data = get_cycling_timeseries_2017(station)
    weather_data = get_weather_timeseries_2017()

    merged_df = pd.merge(
        left=weather_data,
        left_index=True,
        right=cycling_data,
        right_index=True,
        how="left"
    ).fillna(method='ffill')

    weather_explanatory = merged_df.iloc[:, :3].to_numpy()
    cyclists_dependent = merged_df.iloc[:, 3].to_numpy()

    model = LinearRegression(fit_intercept=True)
    model.fit(weather_explanatory, cyclists_dependent)
    r2 = model.score(weather_explanatory, cyclists_dependent)

    return (tuple(model.coef_), r2)


def main():
    """
    Main function. Prints results from model training.
    """
    station = "Merikannontie"
    coefs, score = cycling_weather_linregr(station)
    print(f"Measuring station: {station}")
    print(
        f"Regression coefficient for variable 'precipitation': {coefs[0]:.1f}")
    print(f"Regression coefficient for variable 'snow depth': {coefs[1]:.1f}")
    print(f"Regression coefficient for variable 'temperature': {coefs[2]:.1f}")
    print(f"Score: {score:.2f}")
    return


if __name__ == "__main__":
    main()
